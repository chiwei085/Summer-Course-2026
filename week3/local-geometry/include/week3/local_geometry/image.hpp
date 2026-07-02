#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <span>
#include <vector>

#include "week3/local_geometry/result.hpp"

namespace week3::local_geometry
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

// An 8-bit-per-channel RGB pixel. Kept trivially copyable so it can sit in a
// tightly packed buffer.
struct Rgb8
{
    std::uint8_t r{0};
    std::uint8_t g{0};
    std::uint8_t b{0};
};

// An owned RGB image: `width * height` pixels, row-major, no padding. The
// class is move-only in spirit (copies are explicit and cheap to reason
// about) and never throws on out-of-range access from its own accessors --
// callers are expected to stay within `size()`.
class Image
{
public:
    Image(ImageSize size, std::vector<Rgb8> pixels);

    [[nodiscard]] ImageSize size() const { return size_; }
    [[nodiscard]] std::span<const Rgb8> pixels() const { return pixels_; }
    [[nodiscard]] std::span<Rgb8> pixels() { return pixels_; }

    [[nodiscard]] const Rgb8& at(int x, int y) const {
        return pixels_[static_cast<std::size_t>(y) * size_.width + x];
    }
    [[nodiscard]] Rgb8& at(int x, int y) {
        return pixels_[static_cast<std::size_t>(y) * size_.width + x];
    }

private:
    ImageSize size_{};
    std::vector<Rgb8> pixels_;
};

struct LoadImageError
{
    std::string message;
};

[[nodiscard]] Result<Image, LoadImageError> load_rgb_image(
    const std::filesystem::path& path);

// Encodes an RGB image as a PNG held entirely in memory, so it can be
// streamed straight into an HTTP response body without touching disk.
[[nodiscard]] std::vector<std::uint8_t> encode_png(const Image& image);

// Produces a downscaled RGB image by resizing with nearest-neighbor
// sampling. Used to keep large source photos responsive in the browser.
[[nodiscard]] Image resize_nearest(const Image& image, ImageSize target);

}  // namespace week3::local_geometry
