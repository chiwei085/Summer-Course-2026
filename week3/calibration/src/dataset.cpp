#include <week3/calibration/dataset.hpp>

#include <algorithm>
#include <charconv>
#include <fstream>
#include <string_view>

namespace week3
{
namespace
{

template <class T>
Result<T, Error> parse_number(std::string_view text, std::string_view label) {
    T out{};
    const auto* begin = text.data();
    const auto* end = text.data() + text.size();
    const auto [ptr, ec] = std::from_chars(begin, end, out);
    if (ec != std::errc{} || ptr != end) {
        return Result<T, Error>::err({.message = "failed to parse " +
                                                 std::string{label} + ": " +
                                                 std::string{text}});
    }
    return Result<T, Error>::ok(out);
}

std::vector<std::string> split_csv_line(std::string_view line) {
    if (!line.empty() && line.back() == '\r') {
        line.remove_suffix(1);
    }
    std::vector<std::string> fields;
    std::size_t start = 0;
    while (start <= line.size()) {
        const std::size_t comma = line.find(',', start);
        if (comma == std::string_view::npos) {
            fields.emplace_back(line.substr(start));
            break;
        }
        fields.emplace_back(line.substr(start, comma - start));
        start = comma + 1;
    }
    return fields;
}

Result<BoardSpec, Error> load_board_spec(const std::filesystem::path& path) {
    std::ifstream input{path};
    if (!input) {
        return Result<BoardSpec, Error>::err(
            {.message = "failed to open board spec: " + path.string()});
    }

    BoardSpec board{};
    std::string line;
    while (std::getline(input, line)) {
        if (line.empty()) {
            continue;
        }
        const auto equals = line.find('=');
        if (equals == std::string::npos) {
            return Result<BoardSpec, Error>::err(
                {.message = "invalid board spec line: " + line});
        }
        const std::string_view key{line.data(), equals};
        const std::string_view value{line.data() + equals + 1,
                                     line.size() - equals - 1};
        if (key == "cols") {
            auto parsed = parse_number<int>(value, "cols");
            if (parsed.is_err()) {
                return Result<BoardSpec, Error>::err(parsed.error());
            }
            board.cols = parsed.value();
        }
        else if (key == "rows") {
            auto parsed = parse_number<int>(value, "rows");
            if (parsed.is_err()) {
                return Result<BoardSpec, Error>::err(parsed.error());
            }
            board.rows = parsed.value();
        }
        else if (key == "square_size") {
            auto parsed = parse_number<double>(value, "square_size");
            if (parsed.is_err()) {
                return Result<BoardSpec, Error>::err(parsed.error());
            }
            board.square_size = parsed.value();
        }
    }

    if (board.cols <= 0 || board.rows <= 0 || board.square_size <= 0.0) {
        return Result<BoardSpec, Error>::err(
            {.message = "board spec must define positive cols, rows, and "
                        "square_size"});
    }
    return Result<BoardSpec, Error>::ok(board);
}

Result<std::map<std::string, std::vector<Observation>>, Error>
load_observations(const std::filesystem::path& path, const BoardSpec& board) {
    std::ifstream input{path};
    if (!input) {
        return Result<std::map<std::string, std::vector<Observation>>,
                      Error>::err({.message =
                                       "failed to open observations CSV: " +
                                       path.string()});
    }

    std::string line;
    auto strip_carriage_return = [](std::string& value) {
        if (!value.empty() && value.back() == '\r') {
            value.pop_back();
        }
    };
    if (!std::getline(input, line)) {
        return Result<std::map<std::string, std::vector<Observation>>,
                      Error>::err({.message = "observations.csv is empty"});
    }
    strip_carriage_return(line);
    if (line != "image,row,col,x_px,y_px") {
        return Result<std::map<std::string, std::vector<Observation>>, Error>::
            err({.message = "observations.csv has an unexpected header"});
    }

    std::map<std::string, std::vector<Observation>> grouped;
    int line_number = 1;
    while (std::getline(input, line)) {
        ++line_number;
        if (line.empty()) {
            continue;
        }
        const auto fields = split_csv_line(line);
        if (fields.size() != 5) {
            return Result<std::map<std::string, std::vector<Observation>>,
                          Error>::err({.message =
                                           "invalid CSV field count at line " +
                                           std::to_string(line_number)});
        }

        auto row = parse_number<int>(fields[1], "row");
        auto col = parse_number<int>(fields[2], "col");
        auto x = parse_number<double>(fields[3], "x_px");
        auto y = parse_number<double>(fields[4], "y_px");
        if (row.is_err()) {
            return Result<std::map<std::string, std::vector<Observation>>,
                          Error>::err(row.error());
        }
        if (col.is_err()) {
            return Result<std::map<std::string, std::vector<Observation>>,
                          Error>::err(col.error());
        }
        if (x.is_err()) {
            return Result<std::map<std::string, std::vector<Observation>>,
                          Error>::err(x.error());
        }
        if (y.is_err()) {
            return Result<std::map<std::string, std::vector<Observation>>,
                          Error>::err(y.error());
        }
        if (row.value() < 0 || row.value() >= board.rows || col.value() < 0 ||
            col.value() >= board.cols) {
            return Result<
                std::map<std::string, std::vector<Observation>>,
                Error>::err({.message = "corner index outside board at line " +
                                        std::to_string(line_number)});
        }

        grouped[fields[0]].push_back({
            .row = row.value(),
            .col = col.value(),
            .pixel = {.x = x.value(), .y = y.value()},
        });
    }

    return Result<std::map<std::string, std::vector<Observation>>, Error>::ok(
        std::move(grouped));
}

}  // namespace

linalg::Vec2 board_point(const BoardSpec& board,
                         const Observation& observation) {
    return {
        .x = static_cast<double>(observation.col) * board.square_size,
        .y = static_cast<double>(observation.row) * board.square_size,
    };
}

Result<CalibrationDataset, Error> load_calibration_dataset(
    const std::filesystem::path& root) {
    auto board = load_board_spec(root / "board.txt");
    if (board.is_err()) {
        return Result<CalibrationDataset, Error>::err(board.error());
    }

    auto grouped = load_observations(root / "observations.csv", board.value());
    if (grouped.is_err()) {
        return Result<CalibrationDataset, Error>::err(grouped.error());
    }

    std::vector<ImageObservations> images;
    for (auto& [image_name, corners] : grouped.value()) {
        if (static_cast<int>(corners.size()) != board.value().corner_count()) {
            return Result<CalibrationDataset, Error>::err(
                {.message = image_name + " has " +
                            std::to_string(corners.size()) +
                            " observations, expected " +
                            std::to_string(board.value().corner_count())});
        }

        std::ranges::sort(corners, {}, [](const Observation& observation) {
            return observation.row * 1000 + observation.col;
        });

        auto image = load_grayscale_image(root / "images" / image_name);
        if (image.is_err()) {
            return Result<CalibrationDataset, Error>::err(
                {.message = image.error().message});
        }

        images.push_back({
            .image_name = image_name,
            .image_size = image.value().size(),
            .corners = std::move(corners),
        });
    }

    if (images.size() < 3) {
        return Result<CalibrationDataset, Error>::err(
            {.message = "camera calibration needs at least 3 valid images"});
    }

    return Result<CalibrationDataset, Error>::ok({
        .board = board.value(),
        .images = std::move(images),
    });
}

}  // namespace week3
