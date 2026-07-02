#pragma once

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "px4_messages.hpp"

namespace week4::homework::mission {

struct MissionParseError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

inline std::string trim(std::string_view text) {
    const auto first = text.find_first_not_of(" \t\r\n");
    if (first == std::string_view::npos) {
        return {};
    }
    const auto last = text.find_last_not_of(" \t\r\n");
    return std::string{text.substr(first, last - first + 1)};
}

inline std::vector<std::string> split_csv_line(std::string_view line) {
    std::vector<std::string> fields;
    std::string current;
    bool quoted = false;
    for (const char c : line) {
        if (c == '"') {
            quoted = !quoted;
        } else if (c == ',' && !quoted) {
            fields.push_back(trim(current));
            current.clear();
        } else {
            current.push_back(c);
        }
    }
    fields.push_back(trim(current));
    return fields;
}

inline bool equals_ignore_case(std::string_view a, std::string_view b) {
    return a.size() == b.size() &&
           std::equal(a.begin(), a.end(), b.begin(), [](char lhs, char rhs) {
               return std::toupper(static_cast<unsigned char>(lhs)) ==
                      std::toupper(static_cast<unsigned char>(rhs));
           });
}

inline void require_set(double value, int row, std::string_view field) {
    if (!px4::is_set(value)) {
        throw MissionParseError{"row " + std::to_string(row) + " field " +
                                std::string(field) + " must be set"};
    }
}

inline double parse_double_field(std::string_view raw, int row,
                                 std::string_view field) {
    // split_csv_line already trims each field before this is called.
    if (raw.empty() || equals_ignore_case(raw, "NaN")) {
        return px4::kNaN;
    }
    const std::string text{raw};
    try {
        std::size_t consumed = 0;
        const double value = std::stod(text, &consumed);
        if (consumed != text.size()) {
            throw MissionParseError{"row " + std::to_string(row) + " field " +
                                    std::string(field) + " has trailing characters"};
        }
        return value;
    } catch (const std::invalid_argument &) {
        throw MissionParseError{"row " + std::to_string(row) + " field " +
                                std::string(field) + " is not a number"};
    } catch (const std::out_of_range &) {
        throw MissionParseError{"row " + std::to_string(row) + " field " +
                                std::string(field) + " is out of range"};
    }
}

inline int parse_int_field(std::string_view raw, int row, std::string_view field) {
    const double value = parse_double_field(raw, row, field);
    require_set(value, row, field);
    return static_cast<int>(value);
}

inline std::uint64_t parse_uint64_field(std::string_view raw, int row,
                                        std::string_view field) {
    const double value = parse_double_field(raw, row, field);
    require_set(value, row, field);
    if (value < 0.0) {
        throw MissionParseError{"row " + std::to_string(row) + " field " +
                                std::string(field) +
                                " must be a non-negative timestamp"};
    }
    return static_cast<std::uint64_t>(value);
}

inline px4::MissionCommand parse_command(std::string_view raw, int row) {
    if (equals_ignore_case(raw, "TAKEOFF")) {
        return px4::MissionCommand::takeoff;
    }
    if (equals_ignore_case(raw, "WAYPOINT")) {
        return px4::MissionCommand::waypoint;
    }
    if (equals_ignore_case(raw, "ROI_WAYPOINT")) {
        return px4::MissionCommand::roi_waypoint;
    }
    if (equals_ignore_case(raw, "CHANGE_SPEED")) {
        return px4::MissionCommand::change_speed;
    }
    if (equals_ignore_case(raw, "LOITER_TIME")) {
        return px4::MissionCommand::loiter_time;
    }
    if (equals_ignore_case(raw, "LAND")) {
        return px4::MissionCommand::land;
    }
    throw MissionParseError{"row " + std::to_string(row) +
                            " command is unsupported: " + std::string(raw)};
}

inline px4::MissionFrame parse_frame(std::string_view raw, int row) {
    if (equals_ignore_case(raw, "LOCAL_NED")) {
        return px4::MissionFrame::local_ned;
    }
    if (equals_ignore_case(raw, "BODY_OFFSET_NED")) {
        return px4::MissionFrame::body_offset_ned;
    }
    throw MissionParseError{"row " + std::to_string(row) +
                            " frame is unsupported: " + std::string(raw)};
}

inline void validate_item(const px4::RawMissionItem &item, int row) {
    if (item.seq < 0) {
        throw MissionParseError{"row " + std::to_string(row) +
                                " seq must be non-negative"};
    }
    if (px4::is_set(item.acceptance_radius_m) && item.acceptance_radius_m <= 0.0) {
        throw MissionParseError{"row " + std::to_string(row) +
                                " acceptance_radius_m must be positive"};
    }
    if (px4::is_set(item.hold_s) && item.hold_s < 0.0) {
        throw MissionParseError{"row " + std::to_string(row) +
                                " hold_s must be non-negative"};
    }
    if (px4::is_set(item.cruise_speed_mps) && item.cruise_speed_mps <= 0.0) {
        throw MissionParseError{"row " + std::to_string(row) +
                                " cruise_speed_mps must be positive"};
    }

    switch (item.command) {
    case px4::MissionCommand::takeoff:
    case px4::MissionCommand::waypoint:
    case px4::MissionCommand::roi_waypoint:
    case px4::MissionCommand::land:
        require_set(item.x, row, "x");
        require_set(item.y, row, "y");
        require_set(item.z, row, "z");
        break;
    case px4::MissionCommand::change_speed:
        require_set(item.cruise_speed_mps, row, "cruise_speed_mps");
        break;
    case px4::MissionCommand::loiter_time:
        require_set(item.hold_s, row, "hold_s");
        break;
    }

    if (item.command == px4::MissionCommand::roi_waypoint ||
        item.command == px4::MissionCommand::loiter_time) {
        require_set(item.roi_x, row, "roi_x");
        require_set(item.roi_y, row, "roi_y");
        require_set(item.roi_z, row, "roi_z");
    }
    if (item.command == px4::MissionCommand::takeoff && item.z >= -0.5) {
        throw MissionParseError{"row " + std::to_string(row) +
                                " TAKEOFF z must be negative in NED"};
    }
    if (item.command == px4::MissionCommand::land && item.z < -0.2) {
        throw MissionParseError{"row " + std::to_string(row) +
                                " LAND z should be near ground in NED"};
    }
}

inline std::vector<px4::RawMissionItem> read_raw_mission_csv(const std::string &path) {
    std::ifstream input{path};
    if (!input) {
        throw MissionParseError{"failed to open raw mission CSV: " + path};
    }

    std::string line;
    if (!std::getline(input, line)) {
        throw MissionParseError{"raw mission CSV is empty"};
    }
    const auto header = split_csv_line(line);
    constexpr std::size_t kExpectedFields = 15;
    if (header.size() != kExpectedFields) {
        throw MissionParseError{"raw mission CSV header has " +
                                std::to_string(header.size()) + " fields, expected " +
                                std::to_string(kExpectedFields)};
    }

    std::vector<px4::RawMissionItem> items;
    int row = 1;
    std::uint64_t previous_timestamp = 0;
    while (std::getline(input, line)) {
        ++row;
        if (trim(line).empty()) {
            continue;
        }
        const auto fields = split_csv_line(line);
        if (fields.size() != kExpectedFields) {
            throw MissionParseError{
                "row " + std::to_string(row) + " has " + std::to_string(fields.size()) +
                " fields, expected " + std::to_string(kExpectedFields)};
        }

        px4::RawMissionItem item;
        item.seq = parse_int_field(fields[0], row, "seq");
        item.timestamp_us = parse_uint64_field(fields[1], row, "timestamp_us");
        item.command = parse_command(fields[2], row);
        item.frame = parse_frame(fields[3], row);
        item.x = parse_double_field(fields[4], row, "x");
        item.y = parse_double_field(fields[5], row, "y");
        item.z = parse_double_field(fields[6], row, "z");
        item.yaw_deg = parse_double_field(fields[7], row, "yaw_deg");
        item.acceptance_radius_m =
            parse_double_field(fields[8], row, "acceptance_radius_m");
        item.hold_s = parse_double_field(fields[9], row, "hold_s");
        item.cruise_speed_mps = parse_double_field(fields[10], row, "cruise_speed_mps");
        item.loiter_radius_m = parse_double_field(fields[11], row, "loiter_radius_m");
        item.roi_x = parse_double_field(fields[12], row, "roi_x");
        item.roi_y = parse_double_field(fields[13], row, "roi_y");
        item.roi_z = parse_double_field(fields[14], row, "roi_z");

        validate_item(item, row);
        if (!items.empty() && item.timestamp_us < previous_timestamp) {
            throw MissionParseError{"row " + std::to_string(row) +
                                    " timestamp_us is not monotonic"};
        }
        previous_timestamp = item.timestamp_us;
        items.push_back(item);
    }

    if (items.size() < 2) {
        throw MissionParseError{"raw mission needs at least two mission items"};
    }
    if (items.front().command != px4::MissionCommand::takeoff) {
        throw MissionParseError{"first mission item must be TAKEOFF"};
    }
    if (items.back().command != px4::MissionCommand::land) {
        throw MissionParseError{"last mission item must be LAND"};
    }
    return items;
}

} // namespace week4::homework::mission
