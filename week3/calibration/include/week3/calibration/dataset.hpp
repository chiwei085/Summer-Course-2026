#pragma once

#include <week3/calibration/image.hpp>
#include <week3/calibration/linalg.hpp>
#include <week3/calibration/result.hpp>

#include <filesystem>
#include <map>
#include <string>
#include <vector>

namespace week3
{

struct BoardSpec
{
    int cols{0};
    int rows{0};
    double square_size{1.0};

    [[nodiscard]] int corner_count() const { return cols * rows; }
};

struct Observation
{
    int row{0};
    int col{0};
    linalg::Vec2 pixel{};
};

struct ImageObservations
{
    std::string image_name;
    ImageSize image_size{};
    std::vector<Observation> corners;
};

struct CalibrationDataset
{
    BoardSpec board;
    std::vector<ImageObservations> images;
};

[[nodiscard]] Result<CalibrationDataset, Error> load_calibration_dataset(
    const std::filesystem::path& root);

[[nodiscard]] linalg::Vec2 board_point(const BoardSpec& board,
                                       const Observation& observation);

}  // namespace week3
