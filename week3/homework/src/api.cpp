#include "week3/snake/api.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <charconv>

#include "week3/snake/config.hpp"
#include "week3/snake/filters.hpp"
#include "week3/snake/initial_contour.hpp"
#include "week3/snake/snake.hpp"

namespace week3::snake
{
namespace
{

using Json = nlohmann::json;

// Every request downscales its source image before running any algorithm,
// both so the notebook stays responsive on a full-resolution photo and so a
// contour JSON response's (x, y) coordinates line up 1:1 with the PNG the
// browser is displaying.
constexpr int kDefaultMaxWidth = 520;

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

int parse_image_id(const Request& req) {
    return std::clamp(parse_int(req, "id", 1), 1, 3);
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

const InitialContourParams& default_init_params(int id) {
    switch (id) {
        case 2:
            return config::Image2::init;
        case 3:
            return config::Image3::init;
        default:
            return config::Image1::init;
    }
}

const SnakeParams& default_snake_params(int id) {
    switch (id) {
        case 2:
            return config::Image2::snake;
        case 3:
            return config::Image3::snake;
        default:
            return config::Image1::snake;
    }
}

InitialContourParams init_params_from_request(const Request& req,
                                              const InitialContourParams& d) {
    return InitialContourParams{
        .blur_sigma = parse_double(req, "init_blur_sigma", d.blur_sigma),
        .shrink_factor = std::clamp(
            parse_double(req, "init_shrink_factor", d.shrink_factor), 0.1, 1.0),
        .cluster_gap_px = std::max(
            0, parse_int(req, "init_cluster_gap_px", d.cluster_gap_px)),
        .num_points =
            std::clamp(parse_int(req, "points", d.num_points), 8, 300),
    };
}

SnakeParams snake_params_from_request(const Request& req,
                                      const SnakeParams& d) {
    return SnakeParams{
        .alpha = std::max(0.0, parse_double(req, "alpha", d.alpha)),
        .beta = std::max(0.0, parse_double(req, "beta", d.beta)),
        .gamma = std::max(0.0, parse_double(req, "gamma", d.gamma)),
        .energy_sigma =
            std::max(0.0, parse_double(req, "energy_sigma", d.energy_sigma)),
        .search_radius =
            std::clamp(parse_int(req, "search_radius", d.search_radius), 1, 8),
        .iterations =
            std::clamp(parse_int(req, "iterations", d.iterations), 1, 400),
    };
}

Json point_json(const Point2d& p) {
    return Json{{"x", p.x}, {"y", p.y}};
}

Json points_json(const std::vector<Point2d>& points) {
    Json arr = Json::array();
    for (const Point2d& p : points) arr.push_back(point_json(p));
    return arr;
}

}  // namespace

Result<App, AppError> App::load(std::filesystem::path image1_path,
                                std::filesystem::path image2_path,
                                std::filesystem::path image3_path) {
    auto img1 = load_rgb_image(image1_path);
    if (img1.is_err())
        return Result<App, AppError>::err({.message = img1.error().message});
    auto img2 = load_rgb_image(image2_path);
    if (img2.is_err())
        return Result<App, AppError>::err({.message = img2.error().message});
    auto img3 = load_rgb_image(image3_path);
    if (img3.is_err())
        return Result<App, AppError>::err({.message = img3.error().message});

    return Result<App, AppError>::ok(App{
        std::array<Image, 3>{std::move(img1.value()), std::move(img2.value()),
                             std::move(img3.value())}});
}

Response App::handle_source(const Request& req) const {
    const int id = parse_image_id(req);
    return Response::png(encode_png(
        scaled_source(images_[static_cast<std::size_t>(id - 1)], req)));
}

Response App::handle_grayscale(const Request& req) const {
    const int id = parse_image_id(req);
    const Image scaled =
        scaled_source(images_[static_cast<std::size_t>(id - 1)], req);
    const double sigma = std::max(
        0.0, parse_double(req, "sigma", default_init_params(id).blur_sigma));
    const GrayImage gray = gaussian_blur(to_grayscale(scaled), sigma);
    return Response::png(encode_png(visualize_gray(gray)));
}

Response App::handle_gradient(const Request& req) const {
    const int id = parse_image_id(req);
    const Image scaled =
        scaled_source(images_[static_cast<std::size_t>(id - 1)], req);
    const double sigma = std::max(
        0.0, parse_double(req, "sigma", default_init_params(id).blur_sigma));
    const GrayImage gray = gaussian_blur(to_grayscale(scaled), sigma);
    return Response::png(
        encode_png(visualize_gray(sobel_gradients(gray).magnitude)));
}

Response App::handle_defaults(const Request& req) const {
    const int id = parse_image_id(req);
    const InitialContourParams& ip = default_init_params(id);
    const SnakeParams& sp = default_snake_params(id);
    Json out;
    out["init"] = Json{
        {"blur_sigma", ip.blur_sigma},
        {"shrink_factor", ip.shrink_factor},
        {"cluster_gap_px", ip.cluster_gap_px},
        {"num_points", ip.num_points},
    };
    out["snake"] = Json{
        {"alpha", sp.alpha},
        {"beta", sp.beta},
        {"gamma", sp.gamma},
        {"energy_sigma", sp.energy_sigma},
        {"search_radius", sp.search_radius},
        {"iterations", sp.iterations},
    };
    return Response::json(out.dump());
}

Response App::handle_init(const Request& req) const {
    const int id = parse_image_id(req);
    const Image scaled =
        scaled_source(images_[static_cast<std::size_t>(id - 1)], req);
    const InitialContourParams params =
        init_params_from_request(req, default_init_params(id));
    const InitialContour contour =
        find_initial_contour(to_grayscale(scaled), params);

    Json out;
    out["image_width"] = scaled.size().width;
    out["image_height"] = scaled.size().height;
    out["points"] = points_json(contour.points);
    out["bbox"] = Json{{"x0", contour.bbox_x0},
                       {"y0", contour.bbox_y0},
                       {"x1", contour.bbox_x1},
                       {"y1", contour.bbox_y1}};
    return Response::json(out.dump());
}

Response App::handle_run(const Request& req) const {
    const int id = parse_image_id(req);
    const Image scaled =
        scaled_source(images_[static_cast<std::size_t>(id - 1)], req);
    const GrayImage gray = to_grayscale(scaled);

    const InitialContourParams init_params =
        init_params_from_request(req, default_init_params(id));
    const InitialContour contour = find_initial_contour(gray, init_params);

    const SnakeParams snake_params =
        snake_params_from_request(req, default_snake_params(id));
    const SnakeRun run = run_snake(gray, contour.points, snake_params);

    Json out;
    out["image_width"] = scaled.size().width;
    out["image_height"] = scaled.size().height;
    Json frames = Json::array();
    for (const std::vector<Point2d>& frame : run.history)
        frames.push_back(points_json(frame));
    out["frames"] = std::move(frames);
    return Response::json(out.dump());
}

HttpServer::Builder register_routes(HttpServer::Builder builder, const App& app,
                                    std::filesystem::path web_root) {
    return std::move(builder)
        .get("/api/source",
             [&app](const Request& req) { return app.handle_source(req); })
        .get("/api/grayscale",
             [&app](const Request& req) { return app.handle_grayscale(req); })
        .get("/api/gradient",
             [&app](const Request& req) { return app.handle_gradient(req); })
        .get("/api/defaults",
             [&app](const Request& req) { return app.handle_defaults(req); })
        .get("/api/init",
             [&app](const Request& req) { return app.handle_init(req); })
        .get("/api/run",
             [&app](const Request& req) { return app.handle_run(req); })
        .static_dir("/", std::move(web_root));
}

}  // namespace week3::snake
