#include <cstdlib>
#include <iostream>
#include <string>

#include "visual_relay/protocol.hpp"

using namespace visual_relay;

namespace
{

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        std::exit(1);
    }
}

}  // namespace

int main() {
    TrackUpdate update;
    update.session_id = 42;
    update.track_id = 7;
    update.sequence = 11;
    update.capture_time_ns = 1000;
    update.belt_position_m = 1.25F;
    update.velocity_mps = 0.6F;
    update.predicted_exit_time_s = 3.4F;
    update.confidence = 0.91F;

    const auto bytes = serialize_track_update(update);
    const auto parsed = parse_track_update(bytes);
    expect(parsed.session_id == update.session_id, "session roundtrip");
    expect(parsed.track_id == update.track_id, "track roundtrip");
    expect(parsed.sequence == update.sequence, "sequence roundtrip");
    expect(parsed.checksum != 0, "checksum populated");
    expect(is_fresh_track_update(parsed, 42, 10, 1500, 1000),
           "fresh update accepted");
    expect(!is_fresh_track_update(parsed, 42, 11, 1500, 1000),
           "duplicate sequence rejected");
    expect(!is_fresh_track_update(parsed, 99, 10, 1500, 1000),
           "wrong session rejected");
    expect(!is_fresh_track_update(parsed, 42, 10, 3000, 1000),
           "stale update rejected");

    auto broken = bytes;
    broken[12] ^= 0x7f;
    bool rejected = false;
    try {
        (void)parse_track_update(broken);
    }
    catch (const ProtocolError&) {
        rejected = true;
    }
    expect(rejected, "corrupt update rejected");

    auto frame =
        make_text_message(MessageType::handoff_commit, 42, 100, 100, "track=7");
    const auto packed = serialize_message(frame);
    const auto parsed_frame = parse_message(packed);
    expect(parsed_frame.header.magic == kMessageMagic,
           "message magic roundtrip");
    expect(parsed_frame.header.message_type ==
               static_cast<std::uint16_t>(MessageType::handoff_commit),
           "message type roundtrip");
    expect(std::string(parsed_frame.payload.begin(),
                       parsed_frame.payload.end()) == "track=7",
           "message payload roundtrip");

    MessageFrame too_large =
        make_text_message(MessageType::error, 42, 101, 0, "x");
    too_large.payload.assign(kMaxMessagePayloadSize + 1, std::uint8_t{'x'});
    bool oversized_rejected = false;
    try {
        (void)parse_message(serialize_message(too_large));
    }
    catch (const ProtocolError&) {
        oversized_rejected = true;
    }
    expect(oversized_rejected, "oversized message rejected");

    std::cout << "protocol tests passed\n";
    return 0;
}
