#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace visual_relay
{

constexpr std::uint32_t kTrackUpdateMagic = 0x56525455;  // VRTU
constexpr std::uint32_t kMessageMagic = 0x5652464d;      // VRFM
constexpr std::uint16_t kProtocolVersion = 1;
constexpr std::size_t kTrackUpdateWireSize = 60;
constexpr std::size_t kMessageHeaderWireSize = 36;
constexpr std::uint32_t kMaxMessagePayloadSize = 4096;

enum class MessageType : std::uint16_t
{
    hello = 1,
    hello_ack = 2,
    heartbeat = 3,
    handoff_prepare = 10,
    handoff_descriptor = 11,
    handoff_thumbnail = 12,
    handoff_commit = 13,
    handoff_accept = 14,
    handoff_reject = 15,
    handoff_cancel = 16,
    intercept_result = 20,
    error = 99,
};

struct TrackUpdate
{
    std::uint32_t magic = kTrackUpdateMagic;
    std::uint16_t version = kProtocolVersion;
    std::uint16_t flags = 0;
    std::uint64_t session_id = 0;
    std::uint64_t track_id = 0;
    std::uint64_t sequence = 0;
    std::uint64_t capture_time_ns = 0;
    float belt_position_m = 0.0F;
    float velocity_mps = 0.0F;
    float predicted_exit_time_s = 0.0F;
    float confidence = 0.0F;
    std::uint32_t checksum = 0;
};

struct MessageHeader
{
    std::uint32_t magic = kMessageMagic;
    std::uint16_t version = kProtocolVersion;
    std::uint16_t message_type = 0;
    std::uint32_t payload_size = 0;
    std::uint64_t session_id = 0;
    std::uint64_t message_id = 0;
    std::uint64_t correlation_id = 0;
};

struct MessageFrame
{
    MessageHeader header;
    std::vector<std::uint8_t> payload;
};

class ProtocolError : public std::runtime_error
{
public:
    explicit ProtocolError(const std::string& message)
        : std::runtime_error(message) {}
};

std::uint32_t fnv1a32(std::span<const std::uint8_t> bytes);

std::array<std::uint8_t, kTrackUpdateWireSize> serialize_track_update(
    const TrackUpdate& update);
TrackUpdate parse_track_update(std::span<const std::uint8_t> bytes);
bool is_fresh_track_update(const TrackUpdate& incoming,
                           std::uint64_t expected_session_id,
                           std::uint64_t last_sequence, std::uint64_t now_ns,
                           std::uint64_t stale_after_ns);

std::vector<std::uint8_t> serialize_message(const MessageFrame& frame);
MessageFrame parse_message(std::span<const std::uint8_t> bytes);

MessageFrame make_text_message(MessageType type, std::uint64_t session_id,
                               std::uint64_t message_id,
                               std::uint64_t correlation_id,
                               std::string_view text);

}  // namespace visual_relay
