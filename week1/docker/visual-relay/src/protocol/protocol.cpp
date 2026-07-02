#include "visual_relay/protocol.hpp"

#include <bit>
#include <cstring>
#include <limits>
#include <type_traits>

namespace visual_relay
{
namespace
{

template <class T>
void append_scalar(std::vector<std::uint8_t>& out, T value) {
    static_assert(std::is_trivially_copyable_v<T>);
    auto* begin = reinterpret_cast<const std::uint8_t*>(&value);
    out.insert(out.end(), begin, begin + sizeof(T));
}

template <class T, std::size_t N>
void append_scalar(std::array<std::uint8_t, N>& out, std::size_t& offset,
                   T value) {
    static_assert(std::is_trivially_copyable_v<T>);
    std::memcpy(out.data() + offset, &value, sizeof(T));
    offset += sizeof(T);
}

template <class T>
T read_scalar(std::span<const std::uint8_t> bytes, std::size_t& offset) {
    static_assert(std::is_trivially_copyable_v<T>);
    if (offset + sizeof(T) > bytes.size()) {
        throw ProtocolError("truncated protocol field");
    }
    T value{};
    std::memcpy(&value, bytes.data() + offset, sizeof(T));
    offset += sizeof(T);
    return value;
}

void append_header(std::vector<std::uint8_t>& out,
                   const MessageHeader& header) {
    append_scalar(out, header.magic);
    append_scalar(out, header.version);
    append_scalar(out, header.message_type);
    append_scalar(out, header.payload_size);
    append_scalar(out, header.session_id);
    append_scalar(out, header.message_id);
    append_scalar(out, header.correlation_id);
}

MessageHeader read_header(std::span<const std::uint8_t> bytes,
                          std::size_t& offset) {
    MessageHeader header;
    header.magic = read_scalar<std::uint32_t>(bytes, offset);
    header.version = read_scalar<std::uint16_t>(bytes, offset);
    header.message_type = read_scalar<std::uint16_t>(bytes, offset);
    header.payload_size = read_scalar<std::uint32_t>(bytes, offset);
    header.session_id = read_scalar<std::uint64_t>(bytes, offset);
    header.message_id = read_scalar<std::uint64_t>(bytes, offset);
    header.correlation_id = read_scalar<std::uint64_t>(bytes, offset);
    return header;
}

}  // namespace

std::uint32_t fnv1a32(std::span<const std::uint8_t> bytes) {
    std::uint32_t hash = 2166136261U;
    for (const auto byte : bytes) {
        hash ^= byte;
        hash *= 16777619U;
    }
    return hash;
}

std::array<std::uint8_t, kTrackUpdateWireSize> serialize_track_update(
    const TrackUpdate& update) {
    std::array<std::uint8_t, kTrackUpdateWireSize> out{};
    std::size_t offset = 0;
    append_scalar(out, offset, update.magic);
    append_scalar(out, offset, update.version);
    append_scalar(out, offset, update.flags);
    append_scalar(out, offset, update.session_id);
    append_scalar(out, offset, update.track_id);
    append_scalar(out, offset, update.sequence);
    append_scalar(out, offset, update.capture_time_ns);
    append_scalar(out, offset, update.belt_position_m);
    append_scalar(out, offset, update.velocity_mps);
    append_scalar(out, offset, update.predicted_exit_time_s);
    append_scalar(out, offset, update.confidence);
    append_scalar(out, offset, std::uint32_t{0});

    if (offset != kTrackUpdateWireSize) {
        throw ProtocolError("internal TrackUpdate size mismatch");
    }
    const auto checksum = fnv1a32(std::span<const std::uint8_t>(
        out.data(), out.size() - sizeof(std::uint32_t)));
    std::memcpy(out.data() + out.size() - sizeof(std::uint32_t), &checksum,
                sizeof(checksum));
    return out;
}

TrackUpdate parse_track_update(std::span<const std::uint8_t> bytes) {
    if (bytes.size() != kTrackUpdateWireSize) {
        throw ProtocolError("TrackUpdate has invalid wire size");
    }
    const auto expected =
        fnv1a32(bytes.first(bytes.size() - sizeof(std::uint32_t)));
    std::uint32_t actual{};
    std::memcpy(&actual, bytes.data() + bytes.size() - sizeof(std::uint32_t),
                sizeof(actual));
    if (actual != expected) {
        throw ProtocolError("TrackUpdate checksum mismatch");
    }

    std::size_t offset = 0;
    TrackUpdate update;
    update.magic = read_scalar<std::uint32_t>(bytes, offset);
    update.version = read_scalar<std::uint16_t>(bytes, offset);
    update.flags = read_scalar<std::uint16_t>(bytes, offset);
    update.session_id = read_scalar<std::uint64_t>(bytes, offset);
    update.track_id = read_scalar<std::uint64_t>(bytes, offset);
    update.sequence = read_scalar<std::uint64_t>(bytes, offset);
    update.capture_time_ns = read_scalar<std::uint64_t>(bytes, offset);
    update.belt_position_m = read_scalar<float>(bytes, offset);
    update.velocity_mps = read_scalar<float>(bytes, offset);
    update.predicted_exit_time_s = read_scalar<float>(bytes, offset);
    update.confidence = read_scalar<float>(bytes, offset);
    update.checksum = read_scalar<std::uint32_t>(bytes, offset);

    if (update.magic != kTrackUpdateMagic) {
        throw ProtocolError("TrackUpdate magic mismatch");
    }
    if (update.version != kProtocolVersion) {
        throw ProtocolError("TrackUpdate version mismatch");
    }
    return update;
}

bool is_fresh_track_update(const TrackUpdate& incoming,
                           std::uint64_t expected_session_id,
                           std::uint64_t last_sequence, std::uint64_t now_ns,
                           std::uint64_t stale_after_ns) {
    if (incoming.magic != kTrackUpdateMagic ||
        incoming.version != kProtocolVersion) {
        return false;
    }
    if (incoming.session_id != expected_session_id ||
        incoming.sequence <= last_sequence) {
        return false;
    }
    if (incoming.confidence < 0.20F || incoming.confidence > 1.0F) {
        return false;
    }
    if (incoming.capture_time_ns > now_ns) {
        return false;
    }
    return now_ns - incoming.capture_time_ns <= stale_after_ns;
}

std::vector<std::uint8_t> serialize_message(const MessageFrame& frame) {
    if (frame.payload.size() > std::numeric_limits<std::uint32_t>::max()) {
        throw ProtocolError("payload too large");
    }
    auto header = frame.header;
    header.magic = kMessageMagic;
    header.version = kProtocolVersion;
    header.payload_size = static_cast<std::uint32_t>(frame.payload.size());

    std::vector<std::uint8_t> bytes;
    bytes.reserve(kMessageHeaderWireSize + frame.payload.size());
    append_header(bytes, header);
    bytes.insert(bytes.end(), frame.payload.begin(), frame.payload.end());
    return bytes;
}

MessageFrame parse_message(std::span<const std::uint8_t> bytes) {
    std::size_t offset = 0;
    auto header = read_header(bytes, offset);
    if (header.magic != kMessageMagic) {
        throw ProtocolError("message magic mismatch");
    }
    if (header.version != kProtocolVersion) {
        throw ProtocolError("message version mismatch");
    }
    if (header.payload_size > kMaxMessagePayloadSize) {
        throw ProtocolError("message payload too large");
    }
    if (offset + header.payload_size != bytes.size()) {
        throw ProtocolError("message payload size mismatch");
    }
    MessageFrame frame;
    frame.header = header;
    frame.payload.assign(bytes.begin() + static_cast<std::ptrdiff_t>(offset),
                         bytes.end());
    return frame;
}

MessageFrame make_text_message(MessageType type, std::uint64_t session_id,
                               std::uint64_t message_id,
                               std::uint64_t correlation_id,
                               std::string_view text) {
    MessageFrame frame;
    frame.header.message_type = static_cast<std::uint16_t>(type);
    frame.header.session_id = session_id;
    frame.header.message_id = message_id;
    frame.header.correlation_id = correlation_id;
    frame.payload.assign(text.begin(), text.end());
    return frame;
}

}  // namespace visual_relay
