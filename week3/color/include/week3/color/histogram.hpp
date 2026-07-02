#pragma once

#include <array>
#include <cstdint>

#include "week3/color/color.hpp"
#include "week3/color/image.hpp"

namespace week3::color
{

// A 256-bucket count over one 8-bit channel.
struct Histogram
{
    std::array<std::uint32_t, 256> bins{};

    [[nodiscard]] std::uint32_t max_bin() const;
};

struct ChannelHistograms
{
    Histogram red;
    Histogram green;
    Histogram blue;
    Histogram intensity;
};

[[nodiscard]] Histogram histogram_of_channel(const Image& image,
                                             std::uint8_t Rgb8::* channel);

[[nodiscard]] Histogram histogram_of_intensity(const Image& image,
                                               IntensityMethod method);

[[nodiscard]] ChannelHistograms compute_histograms(const Image& image,
                                                   IntensityMethod method);

}  // namespace week3::color
