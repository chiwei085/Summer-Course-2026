#pragma once

#include <week3/calibration/result.hpp>

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <span>
#include <string>
#include <vector>

namespace week3
{

struct ImageSize
{
    int width{0};
    int height{0};

    [[nodiscard]] std::size_t pixel_count() const {
        return static_cast<std::size_t>(width) *
               static_cast<std::size_t>(height);
    }
};

class Image
{
public:
    Image(ImageSize size, std::vector<std::uint8_t> pixels);

    [[nodiscard]] ImageSize size() const { return size_; }
    [[nodiscard]] std::span<const std::uint8_t> pixels() const {
        return pixels_;
    }

private:
    ImageSize size_{};
    std::vector<std::uint8_t> pixels_;
};

struct LoadImageError
{
    std::string message;
};

[[nodiscard]] Result<Image, LoadImageError> load_grayscale_image(
    const std::filesystem::path& path);

}  // namespace week3
