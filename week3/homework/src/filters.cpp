#include "week3/snake/filters.hpp"

#include <algorithm>
#include <cmath>
#include <deque>
#include <numbers>

namespace week3::snake
{
namespace
{

int clamp_coord(int v, int lo, int hi) {
    return std::clamp(v, lo, hi);
}

// Otsu's method: pick the threshold (over a 0-255 histogram) that maximizes
// between-class variance of foreground vs. background.
int otsu_threshold(const std::vector<int>& histogram, long total) {
    std::vector<double> prob(256);
    for (int i = 0; i < 256; ++i) {
        prob[i] =
            static_cast<double>(histogram[i]) / static_cast<double>(total);
    }
    double global_mean = 0.0;
    for (int i = 0; i < 256; ++i) global_mean += i * prob[i];

    double cumulative_prob = 0.0;
    double cumulative_mean = 0.0;
    double best_variance = -1.0;
    int best_threshold = 0;
    for (int t = 0; t < 256; ++t) {
        cumulative_prob += prob[t];
        cumulative_mean += t * prob[t];
        if (cumulative_prob <= 0.0 || cumulative_prob >= 1.0) continue;
        const double numerator =
            global_mean * cumulative_prob - cumulative_mean;
        const double variance =
            numerator * numerator / (cumulative_prob * (1.0 - cumulative_prob));
        if (variance > best_variance) {
            best_variance = variance;
            best_threshold = t;
        }
    }
    return best_threshold;
}

// Applies a 3x3 kernel at (x, y) with clamp-to-edge borders.
double apply_kernel_3x3(const GrayImage& gray, int x, int y,
                        const double (&kernel)[3][3]) {
    double sum = 0.0;
    for (int ky = -1; ky <= 1; ++ky) {
        const int sy = clamp_coord(y + ky, 0, gray.size.height - 1);
        for (int kx = -1; kx <= 1; ++kx) {
            const int sx = clamp_coord(x + kx, 0, gray.size.width - 1);
            sum += kernel[ky + 1][kx + 1] * gray.at(sx, sy);
        }
    }
    return sum;
}

}  // namespace

GrayImage make_gray_image(ImageSize size, double fill) {
    GrayImage gray;
    gray.size = size;
    gray.pixels.assign(size.pixel_count(), fill);
    return gray;
}

GrayImage to_grayscale(const Image& image) {
    GrayImage gray = make_gray_image(image.size());
    const ImageSize size = image.size();
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            const Rgb8 p = image.at(x, y);
            gray.at(x, y) =
                0.299 * p.r + 0.587 * p.g + 0.114 * p.b;  // BT.601 luma
        }
    }
    return gray;
}

Image visualize_gray(const GrayImage& gray) {
    double min_v = gray.pixels.empty() ? 0.0 : gray.pixels.front();
    double max_v = min_v;
    for (const double v : gray.pixels) {
        min_v = std::min(min_v, v);
        max_v = std::max(max_v, v);
    }
    const double range = max_v - min_v;

    std::vector<Rgb8> pixels(gray.pixels.size());
    for (std::size_t i = 0; i < pixels.size(); ++i) {
        const double normalized =
            range > 1e-9 ? (gray.pixels[i] - min_v) / range : 0.0;
        const auto byte =
            static_cast<std::uint8_t>(std::lround(normalized * 255.0));
        pixels[i] = Rgb8{.r = byte, .g = byte, .b = byte};
    }
    return Image{gray.size, std::move(pixels)};
}

GrayImage gaussian_blur(const GrayImage& gray, double sigma) {
    if (sigma <= 0.0) return gray;

    // Build a 1D Gaussian kernel truncated at 3 standard deviations, the
    // usual cutoff beyond which the tail is negligible.
    const int radius = std::max(1, static_cast<int>(std::ceil(3.0 * sigma)));
    std::vector<double> kernel(2 * radius + 1);
    double sum = 0.0;
    for (int i = -radius; i <= radius; ++i) {
        const double v = std::exp(-(i * i) / (2.0 * sigma * sigma));
        kernel[i + radius] = v;
        sum += v;
    }
    for (double& v : kernel) v /= sum;

    const ImageSize size = gray.size;

    // Horizontal pass.
    GrayImage horizontal = make_gray_image(size);
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            double acc = 0.0;
            for (int k = -radius; k <= radius; ++k) {
                const int sx = clamp_coord(x + k, 0, size.width - 1);
                acc += kernel[k + radius] * gray.at(sx, y);
            }
            horizontal.at(x, y) = acc;
        }
    }

    // Vertical pass.
    GrayImage out = make_gray_image(size);
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            double acc = 0.0;
            for (int k = -radius; k <= radius; ++k) {
                const int sy = clamp_coord(y + k, 0, size.height - 1);
                acc += kernel[k + radius] * horizontal.at(x, sy);
            }
            out.at(x, y) = acc;
        }
    }
    return out;
}

Gradients sobel_gradients(const GrayImage& gray) {
    static constexpr double kSobelX[3][3] = {
        {-1.0, 0.0, 1.0}, {-2.0, 0.0, 2.0}, {-1.0, 0.0, 1.0}};
    static constexpr double kSobelY[3][3] = {
        {-1.0, -2.0, -1.0}, {0.0, 0.0, 0.0}, {1.0, 2.0, 1.0}};

    Gradients out{
        .gx = make_gray_image(gray.size),
        .gy = make_gray_image(gray.size),
        .magnitude = make_gray_image(gray.size),
    };

    for (int y = 0; y < gray.size.height; ++y) {
        for (int x = 0; x < gray.size.width; ++x) {
            const double gx = apply_kernel_3x3(gray, x, y, kSobelX);
            const double gy = apply_kernel_3x3(gray, x, y, kSobelY);
            out.gx.at(x, y) = gx;
            out.gy.at(x, y) = gy;
            out.magnitude.at(x, y) = std::hypot(gx, gy);
        }
    }
    return out;
}

std::vector<std::uint8_t> canny_edges(const GrayImage& gray, double low_ratio) {
    const ImageSize size = gray.size;
    const Gradients gradients = sobel_gradients(gray);

    // Non-maximum suppression: keep a pixel only if its magnitude is a local
    // max along its gradient direction, quantized to the nearest of 4
    // compass directions (0/45/90/135 degrees). This is what turns a wide
    // band of "somewhat high gradient" into a single-pixel-wide ridge.
    std::vector<double> suppressed(size.pixel_count(), 0.0);
    for (int y = 1; y < size.height - 1; ++y) {
        for (int x = 1; x < size.width - 1; ++x) {
            const double gx = gradients.gx.at(x, y);
            const double gy = gradients.gy.at(x, y);
            const double mag = gradients.magnitude.at(x, y);
            if (mag <= 0.0) continue;

            double angle_deg = std::atan2(gy, gx) * 180.0 / std::numbers::pi;
            if (angle_deg < 0.0) angle_deg += 180.0;

            double n1, n2;
            if (angle_deg < 22.5 || angle_deg >= 157.5) {
                n1 = gradients.magnitude.at(x - 1, y);
                n2 = gradients.magnitude.at(x + 1, y);
            } else if (angle_deg < 67.5) {
                n1 = gradients.magnitude.at(x - 1, y - 1);
                n2 = gradients.magnitude.at(x + 1, y + 1);
            } else if (angle_deg < 112.5) {
                n1 = gradients.magnitude.at(x, y - 1);
                n2 = gradients.magnitude.at(x, y + 1);
            } else {
                n1 = gradients.magnitude.at(x + 1, y - 1);
                n2 = gradients.magnitude.at(x - 1, y + 1);
            }
            if (mag >= n1 && mag >= n2) suppressed[static_cast<std::size_t>(y) * size.width + x] = mag;
        }
    }

    // Normalize by the 99th-percentile magnitude (not the raw max) so a
    // handful of specular-highlight pixels can't compress the rest of the
    // histogram toward zero, then let Otsu pick the high threshold with no
    // manual per-image cutoff.
    std::vector<double> sorted_mags{suppressed.begin(), suppressed.end()};
    const std::size_t p99_index =
        static_cast<std::size_t>(sorted_mags.size() * 0.99);
    std::nth_element(sorted_mags.begin(), sorted_mags.begin() + p99_index,
                     sorted_mags.end());
    const double scale_mag = std::max(1e-9, sorted_mags[p99_index]);

    std::vector<int> histogram(256, 0);
    std::vector<std::uint8_t> normalized(size.pixel_count());
    for (std::size_t i = 0; i < normalized.size(); ++i) {
        const int v = std::clamp(
            static_cast<int>(suppressed[i] / scale_mag * 255.0), 0, 255);
        normalized[i] = static_cast<std::uint8_t>(v);
        histogram[static_cast<std::size_t>(v)]++;
    }
    const int high_threshold =
        otsu_threshold(histogram, static_cast<long>(normalized.size()));
    const int low_threshold =
        static_cast<int>(std::clamp(high_threshold * low_ratio, 0.0, 255.0));

    // Hysteresis: BFS out from every strong (>= high) pixel across
    // 8-connected weak (>= low) neighbors, keeping only weak edges actually
    // reachable from a strong one -- an isolated weak pixel from background
    // noise, with no strong edge nearby, gets dropped.
    std::vector<std::uint8_t> out(size.pixel_count(), 0);
    std::vector<char> visited(size.pixel_count(), 0);
    std::deque<std::pair<int, int>> queue;
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            const std::size_t idx = static_cast<std::size_t>(y) * size.width + x;
            if (normalized[idx] >= high_threshold && !visited[idx]) {
                visited[idx] = 1;
                out[idx] = 1;
                queue.emplace_back(x, y);
            }
        }
    }
    while (!queue.empty()) {
        const auto [cx, cy] = queue.front();
        queue.pop_front();
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                if (dx == 0 && dy == 0) continue;
                const int nx = cx + dx;
                const int ny = cy + dy;
                if (nx < 0 || nx >= size.width || ny < 0 || ny >= size.height)
                    continue;
                const std::size_t nidx = static_cast<std::size_t>(ny) * size.width + nx;
                if (visited[nidx] || normalized[nidx] < low_threshold) continue;
                visited[nidx] = 1;
                out[nidx] = 1;
                queue.emplace_back(nx, ny);
            }
        }
    }
    return out;
}

}  // namespace week3::snake
