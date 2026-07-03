#include "week3/snake/initial_contour.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <deque>
#include <utility>

namespace week3::snake
{
namespace
{

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

// A connected blob of foreground-mask pixels, accumulated during BFS
// labeling. Only the bounding box is tracked -- the rectangle fit below
// only ever looks at that, not the blob's actual shape.
struct Component
{
    int size{0};
    int min_x{0};
    int min_y{0};
    int max_x{0};
    int max_y{0};
};

double dist(Point2d a, Point2d b) {
    return std::hypot(a.x - b.x, a.y - b.y);
}

// Resamples a closed polygon into `num_points` points spaced evenly by arc
// length around its perimeter.
std::vector<Point2d> resample_closed_polygon(const std::vector<Point2d>& poly,
                                             int num_points) {
    const int m = static_cast<int>(poly.size());
    std::vector<double> cumulative(m + 1, 0.0);
    for (int i = 0; i < m; ++i) {
        cumulative[i + 1] = cumulative[i] + dist(poly[i], poly[(i + 1) % m]);
    }
    const double perimeter = cumulative[m];

    std::vector<Point2d> out;
    out.reserve(num_points);
    int seg = 0;
    for (int i = 0; i < num_points; ++i) {
        const double target = perimeter * i / num_points;
        while (seg < m - 1 && cumulative[seg + 1] <= target) ++seg;
        const double seg_start = cumulative[seg];
        const double seg_length =
            std::max(1e-9, cumulative[seg + 1] - seg_start);
        const double t = (target - seg_start) / seg_length;
        const Point2d a = poly[seg];
        const Point2d b = poly[(seg + 1) % m];
        out.push_back({.x = a.x + t * (b.x - a.x), .y = a.y + t * (b.y - a.y)});
    }
    return out;
}

InitialContour rectangle_contour(double x0, double y0, double x1, double y1,
                                 int num_points) {
    InitialContour result;
    result.bbox_x0 = x0;
    result.bbox_x1 = x1;
    result.bbox_y0 = y0;
    result.bbox_y1 = y1;
    result.points =
        resample_closed_polygon({{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}},
                                num_points);
    return result;
}

}  // namespace

InitialContour find_initial_contour(const GrayImage& gray,
                                    InitialContourParams params) {
    const GrayImage blurred = gaussian_blur(gray, params.blur_sigma);
    const ImageSize size = gray.size;

    // A single global intensity threshold (Otsu's method), not an edge map:
    // the sample photos are all a darker object against a plain, bright
    // background, so this is enough to separate the two without tracing any
    // boundary detail. Pixels darker than the threshold are "foreground".
    std::vector<int> histogram(256, 0);
    std::vector<std::uint8_t> normalized(size.pixel_count());
    for (std::size_t i = 0; i < normalized.size(); ++i) {
        const int v = std::clamp(static_cast<int>(blurred.pixels[i]), 0, 255);
        normalized[i] = static_cast<std::uint8_t>(v);
        histogram[static_cast<std::size_t>(v)]++;
    }
    const int threshold =
        otsu_threshold(histogram, static_cast<long>(normalized.size()));
    std::vector<std::uint8_t> mask(normalized.size());
    for (std::size_t i = 0; i < normalized.size(); ++i)
        mask[i] = normalized[i] < threshold ? 1 : 0;

    // 8-connected component labeling via BFS flood fill.
    std::vector<int> label(mask.size(), -1);
    std::vector<Component> components;
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            const std::size_t start_idx =
                static_cast<std::size_t>(y) * size.width + x;
            if (!mask[start_idx] || label[start_idx] != -1) continue;

            Component comp;
            comp.min_x = comp.max_x = x;
            comp.min_y = comp.max_y = y;
            const int comp_id = static_cast<int>(components.size());
            std::deque<std::pair<int, int>> queue;
            queue.emplace_back(x, y);
            label[start_idx] = comp_id;
            while (!queue.empty()) {
                const auto [cx, cy] = queue.front();
                queue.pop_front();
                comp.size++;
                comp.min_x = std::min(comp.min_x, cx);
                comp.max_x = std::max(comp.max_x, cx);
                comp.min_y = std::min(comp.min_y, cy);
                comp.max_y = std::max(comp.max_y, cy);

                static constexpr int kDx[8] = {1, -1, 0, 0, 1, 1, -1, -1};
                static constexpr int kDy[8] = {0, 0, 1, -1, 1, -1, 1, -1};
                for (int d = 0; d < 8; ++d) {
                    const int nx = cx + kDx[d];
                    const int ny = cy + kDy[d];
                    if (nx < 0 || nx >= size.width || ny < 0 ||
                        ny >= size.height)
                        continue;
                    const std::size_t nidx =
                        static_cast<std::size_t>(ny) * size.width + nx;
                    if (mask[nidx] && label[nidx] == -1) {
                        label[nidx] = comp_id;
                        queue.emplace_back(nx, ny);
                    }
                }
            }
            components.push_back(comp);
        }
    }

    // Components touching the image border are background/frame, not the
    // object; tiny leftover specks are dropped by a minimum size fraction.
    const double image_area =
        static_cast<double>(size.width) * static_cast<double>(size.height);
    constexpr double kMinComponentAreaFraction = 0.003;
    const Component* best_overall = nullptr;
    std::vector<int> candidates;
    for (int i = 0; i < static_cast<int>(components.size()); ++i) {
        const Component& c = components[static_cast<std::size_t>(i)];
        if (!best_overall || c.size > best_overall->size) best_overall = &c;

        const bool touches_border = c.min_x == 0 || c.min_y == 0 ||
                                    c.max_x == size.width - 1 ||
                                    c.max_y == size.height - 1;
        if (touches_border) continue;
        if (c.size / image_area < kMinComponentAreaFraction) continue;
        candidates.push_back(i);
    }

    // A shiny metal fastener or buckle can threshold to background,
    // splitting an object into pieces that never touch in the mask (e.g. a
    // briefcase's handle, connected to the case only by reflective metal
    // loops) -- so nearby candidates are merged by bounding-box proximity
    // and the resulting cluster's bounding box (the union of its members'
    // boxes, not just the single largest piece) is what gets used below.
    // Without this, a rectangle fit to the case alone would sit entirely
    // below the handle, and the snake -- which can only shrink the contour
    // inward onto nearby gradient, never grow out to something outside its
    // starting box -- would have no way to ever reach it.
    std::vector<int> cluster_parent(candidates.size());
    for (std::size_t i = 0; i < candidates.size(); ++i)
        cluster_parent[i] = static_cast<int>(i);
    auto find_root = [&](int i) {
        while (cluster_parent[static_cast<std::size_t>(i)] != i) {
            const int parent = cluster_parent[static_cast<std::size_t>(i)];
            cluster_parent[static_cast<std::size_t>(i)] =
                cluster_parent[static_cast<std::size_t>(parent)];
            i = parent;
        }
        return i;
    };
    auto bbox_within_gap = [&](const Component& a, const Component& b, int gap) {
        return !(a.max_x + gap < b.min_x || b.max_x + gap < a.min_x ||
                 a.max_y + gap < b.min_y || b.max_y + gap < a.min_y);
    };
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        for (std::size_t j = i + 1; j < candidates.size(); ++j) {
            if (bbox_within_gap(components[static_cast<std::size_t>(candidates[i])],
                                components[static_cast<std::size_t>(candidates[j])],
                                params.cluster_gap_px)) {
                const int ri = find_root(static_cast<int>(i));
                const int rj = find_root(static_cast<int>(j));
                if (ri != rj) cluster_parent[static_cast<std::size_t>(ri)] = rj;
            }
        }
    }

    std::vector<int> cluster_size(candidates.size(), 0);
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        const int root = find_root(static_cast<int>(i));
        cluster_size[static_cast<std::size_t>(root)] +=
            components[static_cast<std::size_t>(candidates[i])].size;
    }
    int best_root = -1;
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        if (best_root == -1 ||
            cluster_size[static_cast<std::size_t>(i)] >
                cluster_size[static_cast<std::size_t>(best_root)])
            best_root = static_cast<int>(i);
    }

    // No non-border candidate survived at all -- fall back to the largest
    // component overall (even if it touches the border) rather than
    // returning nothing, or a centered generic rectangle if there are no
    // components whatsoever.
    if (best_root == -1) {
        if (!best_overall) {
            return rectangle_contour(size.width * 0.15, size.height * 0.15,
                                     size.width * 0.85, size.height * 0.85,
                                     params.num_points);
        }
        const double cx = (best_overall->min_x + best_overall->max_x) / 2.0;
        const double cy = (best_overall->min_y + best_overall->max_y) / 2.0;
        const double half_w =
            (best_overall->max_x - best_overall->min_x) / 2.0 * params.shrink_factor;
        const double half_h =
            (best_overall->max_y - best_overall->min_y) / 2.0 * params.shrink_factor;
        return rectangle_contour(cx - half_w, cy - half_h, cx + half_w,
                                 cy + half_h, params.num_points);
    }

    int min_x = size.width, min_y = size.height, max_x = 0, max_y = 0;
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        if (find_root(static_cast<int>(i)) != best_root) continue;
        const Component& c = components[static_cast<std::size_t>(candidates[i])];
        min_x = std::min(min_x, c.min_x);
        max_x = std::max(max_x, c.max_x);
        min_y = std::min(min_y, c.min_y);
        max_y = std::max(max_y, c.max_y);
    }

    const double cx = (min_x + max_x) / 2.0;
    const double cy = (min_y + max_y) / 2.0;
    const double half_w = (max_x - min_x) / 2.0 * params.shrink_factor;
    const double half_h = (max_y - min_y) / 2.0 * params.shrink_factor;
    return rectangle_contour(cx - half_w, cy - half_h, cx + half_w,
                             cy + half_h, params.num_points);
}

}  // namespace week3::snake
