#include "week3/local_geometry/corners.hpp"

#include <algorithm>
#include <cstddef>

namespace week3::local_geometry
{
namespace
{

// Sums `field` over a (2r+1) x (2r+1) window centered on (x, y), clamped to
// the image bounds. A box filter rather than a Gaussian, matching the
// "sums of Ix^2, Iy^2, IxIy over a window" description of Harris/Shi-Tomasi
// used everywhere from the original 1988 paper onward.
double box_sum(const GrayImage& field, int x, int y, int radius) {
    const int x0 = std::max(0, x - radius);
    const int x1 = std::min(field.size.width - 1, x + radius);
    const int y0 = std::max(0, y - radius);
    const int y1 = std::min(field.size.height - 1, y + radius);
    double sum = 0.0;
    for (int yy = y0; yy <= y1; ++yy) {
        for (int xx = x0; xx <= x1; ++xx) sum += field.at(xx, yy);
    }
    return sum;
}

}  // namespace

StructureTensor structure_tensor(const Gradients& gradients,
                                 int window_radius) {
    const ImageSize size = gradients.gx.size;
    GrayImage ixx_point = make_gray_image(size);
    GrayImage iyy_point = make_gray_image(size);
    GrayImage ixy_point = make_gray_image(size);
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            const double gx = gradients.gx.at(x, y);
            const double gy = gradients.gy.at(x, y);
            ixx_point.at(x, y) = gx * gx;
            iyy_point.at(x, y) = gy * gy;
            ixy_point.at(x, y) = gx * gy;
        }
    }

    StructureTensor out{
        .ixx = make_gray_image(size),
        .iyy = make_gray_image(size),
        .ixy = make_gray_image(size),
    };
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            out.ixx.at(x, y) = box_sum(ixx_point, x, y, window_radius);
            out.iyy.at(x, y) = box_sum(iyy_point, x, y, window_radius);
            out.ixy.at(x, y) = box_sum(ixy_point, x, y, window_radius);
        }
    }
    return out;
}

GrayImage harris_response(const StructureTensor& tensor, double k) {
    const ImageSize size = tensor.ixx.size;
    GrayImage response = make_gray_image(size);
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            const double a = tensor.ixx.at(x, y);
            const double b = tensor.iyy.at(x, y);
            const double c = tensor.ixy.at(x, y);
            const double det = a * b - c * c;
            const double trace = a + b;
            response.at(x, y) = det - k * trace * trace;
        }
    }
    return response;
}

std::vector<Corner> detect_corners(const GrayImage& response, double threshold,
                                   int nms_radius) {
    const ImageSize size = response.size;
    std::vector<Corner> corners;
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            const double value = response.at(x, y);
            if (value < threshold) continue;

            bool is_local_max = true;
            for (int dy = -nms_radius; dy <= nms_radius && is_local_max; ++dy) {
                const int ny = y + dy;
                if (ny < 0 || ny >= size.height) continue;
                for (int dx = -nms_radius; dx <= nms_radius; ++dx) {
                    if (dx == 0 && dy == 0) continue;
                    const int nx = x + dx;
                    if (nx < 0 || nx >= size.width) continue;
                    if (response.at(nx, ny) > value) {
                        is_local_max = false;
                        break;
                    }
                }
            }
            if (is_local_max)
                corners.push_back({.x = x, .y = y, .response = value});
        }
    }
    std::ranges::sort(corners, [](const Corner& a, const Corner& b) {
        return a.response > b.response;
    });
    return corners;
}

}  // namespace week3::local_geometry
