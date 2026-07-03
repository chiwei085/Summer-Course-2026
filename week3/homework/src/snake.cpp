#include "week3/snake/snake.hpp"

#include <algorithm>
#include <cmath>

namespace week3::snake
{
namespace
{

double sample_bilinear(const GrayImage& field, double x, double y) {
    const int x0 =
        std::clamp(static_cast<int>(std::floor(x)), 0, field.size.width - 1);
    const int y0 =
        std::clamp(static_cast<int>(std::floor(y)), 0, field.size.height - 1);
    const int x1 = std::min(x0 + 1, field.size.width - 1);
    const int y1 = std::min(y0 + 1, field.size.height - 1);
    const double fx = std::clamp(x - x0, 0.0, 1.0);
    const double fy = std::clamp(y - y0, 0.0, 1.0);
    const double top = field.at(x0, y0) * (1.0 - fx) + field.at(x1, y0) * fx;
    const double bottom = field.at(x0, y1) * (1.0 - fx) + field.at(x1, y1) * fx;
    return top * (1.0 - fy) + bottom * fy;
}

double dist(Point2d a, Point2d b) {
    return std::hypot(a.x - b.x, a.y - b.y);
}

// One candidate position a point could move to this iteration, with its
// three raw (unnormalized) energy terms.
struct Candidate
{
    Point2d p;
    double econt;
    double ecurv;
    double eimg;
};

}  // namespace

SnakeRun run_snake(const GrayImage& gray,
                   const std::vector<Point2d>& initial_points,
                   SnakeParams params) {
    const GrayImage blurred = gaussian_blur(gray, params.energy_sigma);
    const GrayImage magnitude = sobel_gradients(blurred).magnitude;

    SnakeRun run;
    run.history.push_back(initial_points);

    const int n = static_cast<int>(initial_points.size());
    if (n < 3) return run;

    const double max_x = static_cast<double>(gray.size.width - 1);
    const double max_y = static_cast<double>(gray.size.height - 1);
    std::vector<Point2d> points = initial_points;

    for (int iter = 0; iter < params.iterations; ++iter) {
        // Average point spacing over the current contour, the reference
        // distance the continuity term tries to preserve.
        double avg_dist = 0.0;
        for (int i = 0; i < n; ++i)
            avg_dist += dist(points[i], points[(i + 1) % n]);
        avg_dist /= n;

        std::vector<Point2d> next(static_cast<std::size_t>(n));
        std::vector<Candidate> candidates;
        for (int i = 0; i < n; ++i) {
            const Point2d prev = points[(i - 1 + n) % n];
            const Point2d curr = points[i];
            const Point2d nxt = points[(i + 1) % n];

            candidates.clear();
            const int r = params.search_radius;
            for (int dy = -r; dy <= r; ++dy) {
                for (int dx = -r; dx <= r; ++dx) {
                    Point2d cand{std::clamp(curr.x + dx, 0.0, max_x),
                                 std::clamp(curr.y + dy, 0.0, max_y)};
                    const double d = dist(prev, cand);
                    const double econt = (avg_dist - d) * (avg_dist - d);
                    const double curvx = prev.x - 2.0 * cand.x + nxt.x;
                    const double curvy = prev.y - 2.0 * cand.y + nxt.y;
                    const double ecurv = curvx * curvx + curvy * curvy;
                    const double eimg =
                        -sample_bilinear(magnitude, cand.x, cand.y);
                    candidates.push_back({.p = cand,
                                          .econt = econt,
                                          .ecurv = ecurv,
                                          .eimg = eimg});
                }
            }

            // Normalize each energy term to [0, 1] within this point's
            // candidate window so alpha/beta/gamma weight comparable
            // quantities, matching the classic greedy-snake formulation.
            double min_c = candidates.front().econt, max_c = min_c;
            double min_v = candidates.front().ecurv, max_v = min_v;
            double min_i = candidates.front().eimg, max_i = min_i;
            for (const Candidate& c : candidates) {
                min_c = std::min(min_c, c.econt);
                max_c = std::max(max_c, c.econt);
                min_v = std::min(min_v, c.ecurv);
                max_v = std::max(max_v, c.ecurv);
                min_i = std::min(min_i, c.eimg);
                max_i = std::max(max_i, c.eimg);
            }
            const double range_c = std::max(1e-9, max_c - min_c);
            const double range_v = std::max(1e-9, max_v - min_v);
            const double range_i = std::max(1e-9, max_i - min_i);

            Point2d best_point = curr;
            double best_energy = 0.0;
            bool first = true;
            for (const Candidate& c : candidates) {
                const double nc = (c.econt - min_c) / range_c;
                const double nv = (c.ecurv - min_v) / range_v;
                const double ni = (c.eimg - min_i) / range_i;
                const double e =
                    params.alpha * nc + params.beta * nv + params.gamma * ni;
                if (first || e < best_energy) {
                    best_energy = e;
                    best_point = c.p;
                    first = false;
                }
            }
            next[static_cast<std::size_t>(i)] = best_point;
        }
        points = next;
        run.history.push_back(points);
    }
    return run;
}

}  // namespace week3::snake
