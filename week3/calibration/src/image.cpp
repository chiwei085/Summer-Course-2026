#include <week3/calibration/image.hpp>

#include <algorithm>
#include <memory>

#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

namespace week3
{
namespace
{

struct StbiDeleter
{
    void operator()(std::uint8_t* pixels) const { stbi_image_free(pixels); }
};

using StbiPixels = std::unique_ptr<std::uint8_t, StbiDeleter>;

}  // namespace

Image::Image(ImageSize size, std::vector<std::uint8_t> pixels)
    : size_{size}, pixels_{std::move(pixels)} {}

Result<Image, LoadImageError> load_grayscale_image(
    const std::filesystem::path& path) {
    int width = 0;
    int height = 0;
    int channels_in_file = 0;
    StbiPixels loaded{stbi_load(path.string().c_str(), &width, &height,
                                &channels_in_file, 1)};
    if (!loaded) {
        return Result<Image, LoadImageError>::err(
            {.message = std::string{"failed to load image: "} +
                        stbi_failure_reason() + " (" + path.string() + ")"});
    }
    if (width <= 0 || height <= 0) {
        return Result<Image, LoadImageError>::err(
            {.message = "stb_image returned an invalid image size for " +
                        path.string()});
    }

    const ImageSize size{.width = width, .height = height};
    std::vector<std::uint8_t> pixels(size.pixel_count());
    std::copy_n(loaded.get(), pixels.size(), pixels.begin());
    return Result<Image, LoadImageError>::ok(Image{size, std::move(pixels)});
}

}  // namespace week3
