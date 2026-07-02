#include "week3/color/histogram.hpp"

#include <algorithm>

namespace week3::color
{

std::uint32_t Histogram::max_bin() const {
    return *std::ranges::max_element(bins);
}

Histogram histogram_of_channel(const Image& image,
                               std::uint8_t Rgb8::* channel) {
    Histogram histogram;
    for (const Rgb8& pixel : image.pixels()) {
        ++histogram.bins[pixel.*channel];
    }
    return histogram;
}

Histogram histogram_of_intensity(const Image& image, IntensityMethod method) {
    Histogram histogram;
    for (const Rgb8& pixel : image.pixels()) {
        ++histogram.bins[rgb_to_intensity(pixel, method)];
    }
    return histogram;
}

ChannelHistograms compute_histograms(const Image& image,
                                     IntensityMethod method) {
    return ChannelHistograms{
        .red = histogram_of_channel(image, &Rgb8::r),
        .green = histogram_of_channel(image, &Rgb8::g),
        .blue = histogram_of_channel(image, &Rgb8::b),
        .intensity = histogram_of_intensity(image, method),
    };
}

}  // namespace week3::color
