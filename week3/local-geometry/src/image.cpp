#include "week3/local_geometry/image.hpp"

#include <algorithm>
#include <memory>

#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>

namespace week3::local_geometry
{
namespace
{

struct StbiDeleter
{
    void operator()(std::uint8_t* pixels) const { stbi_image_free(pixels); }
};

using StbiPixels = std::unique_ptr<std::uint8_t, StbiDeleter>;

void append_to_buffer(void* context, void* data, int size) {
    auto* buffer = static_cast<std::vector<std::uint8_t>*>(context);
    const auto* bytes = static_cast<const std::uint8_t*>(data);
    buffer->insert(buffer->end(), bytes, bytes + size);
}

}  // namespace

Image::Image(ImageSize size, std::vector<Rgb8> pixels)
    : size_{size}, pixels_{std::move(pixels)} {}

Result<Image, LoadImageError> load_rgb_image(
    const std::filesystem::path& path) {
    int width = 0;
    int height = 0;
    int channels_in_file = 0;
    StbiPixels loaded{stbi_load(path.string().c_str(), &width, &height,
                                &channels_in_file, 3)};
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
    std::vector<Rgb8> pixels(size.pixel_count());
    const std::uint8_t* src = loaded.get();
    for (std::size_t i = 0; i < pixels.size(); ++i) {
        pixels[i] =
            Rgb8{.r = src[i * 3 + 0], .g = src[i * 3 + 1], .b = src[i * 3 + 2]};
    }
    return Result<Image, LoadImageError>::ok(Image{size, std::move(pixels)});
}

std::vector<std::uint8_t> encode_png(const Image& image) {
    std::vector<std::uint8_t> buffer;
    const ImageSize size = image.size();
    stbi_write_png_to_func(&append_to_buffer, &buffer, size.width, size.height,
                           3, image.pixels().data(),
                           size.width * static_cast<int>(sizeof(Rgb8)));
    return buffer;
}

Image resize_nearest(const Image& image, ImageSize target) {
    const ImageSize source = image.size();
    std::vector<Rgb8> pixels(target.pixel_count());
    for (int y = 0; y < target.height; ++y) {
        const int src_y =
            std::min(source.height - 1, y * source.height / target.height);
        for (int x = 0; x < target.width; ++x) {
            const int src_x =
                std::min(source.width - 1, x * source.width / target.width);
            pixels[static_cast<std::size_t>(y) * target.width + x] =
                image.at(src_x, src_y);
        }
    }
    return Image{target, std::move(pixels)};
}

}  // namespace week3::local_geometry
