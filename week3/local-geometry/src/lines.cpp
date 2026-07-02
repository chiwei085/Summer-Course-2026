#include "week3/local_geometry/lines.hpp"

#include <algorithm>
#include <cmath>
#include <numbers>
#include <vector>

namespace week3::local_geometry
{
namespace
{

struct EdgePoint
{
    int x;
    int y;
};

std::vector<EdgePoint> collect_edge_points(const EdgeMap& edges) {
    std::vector<EdgePoint> points;
    for (int y = 0; y < edges.size.height; ++y) {
        for (int x = 0; x < edges.size.width; ++x) {
            if (edges.is_edge(x, y)) points.push_back({x, y});
        }
    }
    return points;
}

}  // namespace

std::vector<HoughLine> hough_lines(const EdgeMap& edges,
                                   const HoughParams& params) {
    const std::vector<EdgePoint> points = collect_edge_points(edges);
    if (points.empty()) return {};

    const double diag = std::hypot(edges.size.width, edges.size.height);
    const int rho_bins =
        std::max(1, static_cast<int>(std::ceil(2.0 * diag / params.rho_step)));
    const int theta_bins =
        std::max(1, static_cast<int>(std::ceil(180.0 / params.theta_step_deg)));

    std::vector<int> accumulator(static_cast<std::size_t>(rho_bins) *
                                     static_cast<std::size_t>(theta_bins),
                                 0);

    std::vector<double> cos_table(theta_bins);
    std::vector<double> sin_table(theta_bins);
    for (int t = 0; t < theta_bins; ++t) {
        const double theta_rad =
            (t * params.theta_step_deg) * std::numbers::pi / 180.0;
        cos_table[t] = std::cos(theta_rad);
        sin_table[t] = std::sin(theta_rad);
    }

    auto rho_to_bin = [&](double rho) {
        const double shifted = rho + diag;
        return std::clamp(static_cast<int>(shifted / params.rho_step), 0,
                          rho_bins - 1);
    };

    for (const EdgePoint& p : points) {
        for (int t = 0; t < theta_bins; ++t) {
            const double rho = p.x * cos_table[t] + p.y * sin_table[t];
            const int rb = rho_to_bin(rho);
            ++accumulator[static_cast<std::size_t>(rb) * theta_bins + t];
        }
    }

    // Collect every bin clearing the vote threshold, sort by votes
    // descending, then greedily keep peaks that are far enough (in rho and
    // theta) from every peak already kept -- a cheap stand-in for a proper
    // 2D non-max suppression over the accumulator.
    struct Candidate
    {
        int rho_bin;
        int theta_bin;
        int votes;
    };
    std::vector<Candidate> candidates;
    for (int rb = 0; rb < rho_bins; ++rb) {
        for (int t = 0; t < theta_bins; ++t) {
            const int votes =
                accumulator[static_cast<std::size_t>(rb) * theta_bins + t];
            if (votes >= params.threshold) {
                candidates.push_back(
                    {.rho_bin = rb, .theta_bin = t, .votes = votes});
            }
        }
    }
    std::ranges::sort(candidates, [](const Candidate& a, const Candidate& b) {
        return a.votes > b.votes;
    });

    std::vector<HoughLine> lines;
    for (const Candidate& c : candidates) {
        if (static_cast<int>(lines.size()) >= params.max_lines) break;
        const double rho = c.rho_bin * params.rho_step - diag;
        const double theta_deg = c.theta_bin * params.theta_step_deg;

        bool too_close = false;
        for (const HoughLine& kept : lines) {
            const double kept_theta_deg = kept.theta * 180.0 / std::numbers::pi;
            double theta_diff = std::abs(theta_deg - kept_theta_deg);
            theta_diff = std::min(theta_diff, 180.0 - theta_diff);
            const double rho_diff = std::abs(rho - kept.rho);
            if (theta_diff < params.min_theta_separation_deg &&
                rho_diff < params.min_rho_separation) {
                too_close = true;
                break;
            }
        }
        if (too_close) continue;

        lines.push_back({.rho = rho,
                         .theta = theta_deg * std::numbers::pi / 180.0,
                         .votes = c.votes});
    }
    return lines;
}

std::vector<LineSegment> extract_segments(const EdgeMap& edges,
                                          const std::vector<HoughLine>& lines,
                                          const SegmentParams& params) {
    const std::vector<EdgePoint> points = collect_edge_points(edges);
    std::vector<LineSegment> segments;

    for (const HoughLine& line : lines) {
        const double cos_t = std::cos(line.theta);
        const double sin_t = std::sin(line.theta);
        // Point on the line closest to the origin, and the unit direction
        // vector along the line (perpendicular to the line's normal).
        const double base_x = line.rho * cos_t;
        const double base_y = line.rho * sin_t;
        const double dir_x = -sin_t;
        const double dir_y = cos_t;

        struct Projected
        {
            double t;
            double x;
            double y;
        };
        std::vector<Projected> on_line;
        for (const EdgePoint& p : points) {
            const double dx = p.x - base_x;
            const double dy = p.y - base_y;
            const double perp_dist = std::abs(dx * cos_t + dy * sin_t);
            if (perp_dist > params.max_point_distance) continue;
            const double t = dx * dir_x + dy * dir_y;
            on_line.push_back({.t = t,
                               .x = static_cast<double>(p.x),
                               .y = static_cast<double>(p.y)});
        }
        if (on_line.empty()) continue;
        std::ranges::sort(on_line, [](const Projected& a, const Projected& b) {
            return a.t < b.t;
        });

        std::size_t run_start = 0;
        for (std::size_t i = 1; i <= on_line.size(); ++i) {
            const bool end_of_run =
                i == on_line.size() ||
                (on_line[i].t - on_line[i - 1].t) > params.max_gap;
            if (!end_of_run) continue;

            const Projected& first = on_line[run_start];
            const Projected& last = on_line[i - 1];
            const double length = last.t - first.t;
            if (length >= params.min_length) {
                segments.push_back(
                    {.x1 = first.x, .y1 = first.y, .x2 = last.x, .y2 = last.y});
            }
            run_start = i;
        }
    }
    return segments;
}

}  // namespace week3::local_geometry
