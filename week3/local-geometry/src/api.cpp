#include "week3/local_geometry/api.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <charconv>

#include "week3/local_geometry/corners.hpp"
#include "week3/local_geometry/edges.hpp"
#include "week3/local_geometry/gradient.hpp"
#include "week3/local_geometry/lines.hpp"

namespace week3::local_geometry
{
namespace
{

using Json = nlohmann::json;

// Every topic downscales its source image before running any algorithm on
// it, both so the notebook stays responsive on a full-resolution photo and
// so a detection JSON response's (x, y) coordinates line up 1:1 with the
// PNG the browser is displaying -- no separate scale factor to track on the
// frontend.
constexpr int kDefaultMaxWidth = 640;

double parse_double(const Request& req, std::string_view key, double fallback) {
    const Option<std::string> raw = req.query_param(key);
    if (!raw) return fallback;
    double value = fallback;
    const auto* begin = raw->data();
    const auto* end = raw->data() + raw->size();
    const auto result = std::from_chars(begin, end, value);
    return result.ec == std::errc{} ? value : fallback;
}

int parse_int(const Request& req, std::string_view key, int fallback) {
    return static_cast<int>(parse_double(req, key, fallback));
}

Image scaled_for_display(const Image& image, int max_width) {
    const ImageSize size = image.size();
    if (max_width <= 0 || size.width <= max_width) return image;
    const int height = std::max(1, size.height * max_width / size.width);
    return resize_nearest(image,
                          ImageSize{.width = max_width, .height = height});
}

Image scaled_source(const Image& image, const Request& req) {
    return scaled_for_display(image,
                              parse_int(req, "max_width", kDefaultMaxWidth));
}

Json corner_json(const Corner& corner) {
    return Json{
        {"x", corner.x}, {"y", corner.y}, {"response", corner.response}};
}

Json hough_line_json(const HoughLine& line) {
    return Json{
        {"rho", line.rho}, {"theta", line.theta}, {"votes", line.votes}};
}

Json segment_json(const LineSegment& seg) {
    return Json{{"x1", seg.x1}, {"y1", seg.y1}, {"x2", seg.x2}, {"y2", seg.y2}};
}

}  // namespace

Result<App, AppError> App::load(std::filesystem::path edges_image_path,
                                std::filesystem::path corners_image_path,
                                std::filesystem::path lines_image_path) {
    auto edges = load_rgb_image(edges_image_path);
    if (edges.is_err()) {
        return Result<App, AppError>::err({.message = edges.error().message});
    }
    auto corners = load_rgb_image(corners_image_path);
    if (corners.is_err()) {
        return Result<App, AppError>::err({.message = corners.error().message});
    }
    auto lines = load_rgb_image(lines_image_path);
    if (lines.is_err()) {
        return Result<App, AppError>::err({.message = lines.error().message});
    }
    return Result<App, AppError>::ok(App{std::move(edges.value()),
                                         std::move(corners.value()),
                                         std::move(lines.value())});
}

// --- Shared gradient foundation --------------------------------------

Response App::handle_gradient_source(const Request& req) const {
    return Response::png(encode_png(scaled_source(edges_image_, req)));
}

Response App::handle_gradient_magnitude(const Request& req) const {
    const Image scaled = scaled_source(edges_image_, req);
    const GrayImage gray = to_grayscale(scaled);
    const Gradients gradients = sobel_gradients(gray);
    return Response::png(encode_png(visualize_gray(gradients.magnitude)));
}

// --- Edge detection -----------------------------------------------------

Response App::handle_edges_source(const Request& req) const {
    return Response::png(encode_png(scaled_source(edges_image_, req)));
}

Response App::handle_edges_canny(const Request& req) const {
    const Image scaled = scaled_source(edges_image_, req);
    const GrayImage gray = to_grayscale(scaled);
    const CannyParams params{
        .low_threshold = parse_double(req, "low", 30.0),
        .high_threshold = parse_double(req, "high", 90.0),
    };
    const EdgeMap edges = canny(gray, params);
    return Response::png(encode_png(edge_map_to_image(edges)));
}

// --- Corner detection -----------------------------------------------------

Response App::handle_corners_source(const Request& req) const {
    return Response::png(encode_png(scaled_source(corners_image_, req)));
}

Response App::handle_corners_detect(const Request& req) const {
    const Image scaled = scaled_source(corners_image_, req);
    const GrayImage gray = to_grayscale(scaled);
    const Gradients gradients = sobel_gradients(gray);

    const int window_radius = std::max(1, parse_int(req, "window_radius", 2));
    const double k = parse_double(req, "k", 0.04);
    const double threshold = parse_double(req, "threshold", 1.5e12);
    const int nms_radius = std::max(1, parse_int(req, "nms_radius", 4));

    const StructureTensor tensor = structure_tensor(gradients, window_radius);
    const GrayImage response = harris_response(tensor, k);
    std::vector<Corner> corners =
        detect_corners(response, threshold, nms_radius);

    constexpr std::size_t kMaxReturnedCorners = 500;
    if (corners.size() > kMaxReturnedCorners) {
        corners.resize(kMaxReturnedCorners);
    }

    Json out;
    out["image_width"] = scaled.size().width;
    out["image_height"] = scaled.size().height;
    Json corners_json = Json::array();
    for (const Corner& c : corners) corners_json.push_back(corner_json(c));
    out["corners"] = std::move(corners_json);
    return Response::json(out.dump());
}

// --- Line detection -----------------------------------------------------

Response App::handle_lines_source(const Request& req) const {
    return Response::png(encode_png(scaled_source(lines_image_, req)));
}

Response App::handle_lines_detect(const Request& req) const {
    const Image scaled = scaled_source(lines_image_, req);
    const GrayImage gray = to_grayscale(scaled);
    const EdgeMap edges = canny(
        gray, CannyParams{
                  .low_threshold = parse_double(req, "canny_low", 40.0),
                  .high_threshold = parse_double(req, "canny_high", 120.0),
              });

    const HoughParams hough_params{
        .theta_step_deg =
            std::max(0.1, parse_double(req, "theta_step", 1.0)),
        .rho_step = std::max(0.1, parse_double(req, "rho_step", 1.0)),
        .threshold = std::max(1, parse_int(req, "threshold", 180)),
        .max_lines = std::max(1, parse_int(req, "max_lines", 25)),
        .min_theta_separation_deg =
            std::max(0.0, parse_double(req, "min_theta_sep", 5.0)),
        .min_rho_separation =
            std::max(0.0, parse_double(req, "min_rho_sep", 10.0)),
    };
    const std::vector<HoughLine> lines = hough_lines(edges, hough_params);
    const SegmentParams segment_params{
        .max_point_distance =
            std::max(0.1, parse_double(req, "max_point_distance", 3.0)),
        .max_gap = std::max(0.0, parse_double(req, "max_gap", 20.0)),
        .min_length = std::max(0.0, parse_double(req, "min_length", 25.0)),
    };
    const std::vector<LineSegment> segments =
        extract_segments(edges, lines, segment_params);

    Json out;
    out["image_width"] = scaled.size().width;
    out["image_height"] = scaled.size().height;
    Json lines_json = Json::array();
    for (const HoughLine& line : lines)
        lines_json.push_back(hough_line_json(line));
    out["lines"] = std::move(lines_json);
    Json segments_json = Json::array();
    for (const LineSegment& seg : segments)
        segments_json.push_back(segment_json(seg));
    out["segments"] = std::move(segments_json);
    return Response::json(out.dump());
}

HttpServer::Builder register_routes(HttpServer::Builder builder, const App& app,
                                    std::filesystem::path web_root) {
    return std::move(builder)
        .get("/api/gradient/source",
             [&app](const Request& req) {
                 return app.handle_gradient_source(req);
             })
        .get("/api/gradient/magnitude",
             [&app](const Request& req) {
                 return app.handle_gradient_magnitude(req);
             })
        .get(
            "/api/edges/source",
            [&app](const Request& req) { return app.handle_edges_source(req); })
        .get("/api/edges/canny",
             [&app](const Request& req) { return app.handle_edges_canny(req); })
        .get("/api/corners/source",
             [&app](const Request& req) {
                 return app.handle_corners_source(req);
             })
        .get("/api/corners/detect",
             [&app](const Request& req) {
                 return app.handle_corners_detect(req);
             })
        .get(
            "/api/lines/source",
            [&app](const Request& req) { return app.handle_lines_source(req); })
        .get(
            "/api/lines/detect",
            [&app](const Request& req) { return app.handle_lines_detect(req); })
        .static_dir("/vendor/katex",
                    web_root.parent_path() / "third_party" / "katex")
        .static_dir("/", std::move(web_root));
}

}  // namespace week3::local_geometry
