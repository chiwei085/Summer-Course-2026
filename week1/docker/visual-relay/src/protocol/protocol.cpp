#include "visual_relay/protocol.hpp"

#include <algorithm>
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
    std::vector<std::uint8_t> bytes;
    bytes.reserve(kTrackUpdateWireSize);
    append_scalar(bytes, update.magic);
    append_scalar(bytes, update.version);
    append_scalar(bytes, update.flags);
    append_scalar(bytes, update.session_id);
    append_scalar(bytes, update.track_id);
    append_scalar(bytes, update.sequence);
    append_scalar(bytes, update.capture_time_ns);
    append_scalar(bytes, update.belt_position_m);
    append_scalar(bytes, update.velocity_mps);
    append_scalar(bytes, update.predicted_exit_time_s);
    append_scalar(bytes, update.confidence);
    append_scalar(bytes, std::uint32_t{0});

    if (bytes.size() != kTrackUpdateWireSize) {
        throw ProtocolError("internal TrackUpdate size mismatch");
    }
    const auto checksum = fnv1a32(std::span<const std::uint8_t>(
        bytes.data(), bytes.size() - sizeof(std::uint32_t)));
    std::memcpy(bytes.data() + bytes.size() - sizeof(std::uint32_t), &checksum,
                sizeof(checksum));

    std::array<std::uint8_t, kTrackUpdateWireSize> out{};
    std::copy(bytes.begin(), bytes.end(), out.begin());
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
    bytes.reserve(36 + frame.payload.size());
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

std::string_view message_type_name(MessageType type) {
    switch (type) {
        case MessageType::hello:
            return "HELLO";
        case MessageType::hello_ack:
            return "HELLO_ACK";
        case MessageType::heartbeat:
            return "HEARTBEAT";
        case MessageType::handoff_prepare:
            return "HANDOFF_PREPARE";
        case MessageType::handoff_descriptor:
            return "HANDOFF_DESCRIPTOR";
        case MessageType::handoff_thumbnail:
            return "HANDOFF_THUMBNAIL";
        case MessageType::handoff_commit:
            return "HANDOFF_COMMIT";
        case MessageType::handoff_accept:
            return "HANDOFF_ACCEPT";
        case MessageType::handoff_reject:
            return "HANDOFF_REJECT";
        case MessageType::handoff_cancel:
            return "HANDOFF_CANCEL";
        case MessageType::intercept_result:
            return "INTERCEPT_RESULT";
        case MessageType::error:
            return "ERROR";
    }
    return "UNKNOWN";
}

}  // namespace visual_relay
