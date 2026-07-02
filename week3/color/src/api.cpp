#include "week3/color/api.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <charconv>

#include "week3/color/color.hpp"
#include "week3/color/histogram.hpp"

namespace week3::color
{
namespace
{

using Json = nlohmann::json;

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

IntensityMethod parse_intensity_method(const Request& req) {
    const Option<std::string> raw = req.query_param("method");
    if (raw == "average") return IntensityMethod::Average;
    if (raw == "lightness") return IntensityMethod::Lightness;
    return IntensityMethod::Luminosity;
}

Image scaled_for_display(const Image& image, int max_width) {
    const ImageSize size = image.size();
    if (max_width <= 0 || size.width <= max_width) return image;
    const int height = std::max(1, size.height * max_width / size.width);
    return resize_nearest(image,
                          ImageSize{.width = max_width, .height = height});
}

Json histogram_to_json(const Histogram& histogram) {
    Json bins = Json::array();
    for (const std::uint32_t count : histogram.bins) bins.push_back(count);
    return bins;
}

std::uint8_t clamp_channel(double value) {
    return static_cast<std::uint8_t>(std::clamp(value, 0.0, 255.0));
}

}  // namespace

Result<App, AppError> App::load(std::filesystem::path image_path) {
    Result<Image, LoadImageError> loaded = load_rgb_image(image_path);
    if (loaded.is_err()) {
        return Result<App, AppError>::err({.message = loaded.error().message});
    }
    return Result<App, AppError>::ok(App{std::move(loaded.value())});
}

Response App::handle_source_image(const Request& req) const {
    const int max_width = parse_int(req, "max_width", 960);
    return Response::png(encode_png(scaled_for_display(image_, max_width)));
}

Response App::handle_intensity(const Request& req) const {
    const int max_width = parse_int(req, "max_width", 960);
    const IntensityMethod method = parse_intensity_method(req);
    const Image gray = rgb_to_intensity_image(image_, method);
    return Response::png(encode_png(scaled_for_display(gray, max_width)));
}

Response App::handle_histogram(const Request& req) const {
    const IntensityMethod method = parse_intensity_method(req);
    const ChannelHistograms histograms = compute_histograms(image_, method);
    Json out;
    out["red"] = histogram_to_json(histograms.red);
    out["green"] = histogram_to_json(histograms.green);
    out["blue"] = histogram_to_json(histograms.blue);
    out["intensity"] = histogram_to_json(histograms.intensity);
    return Response::json(out.dump());
}

Response App::handle_rgb_to_hsv(const Request& req) const {
    const Rgb8 pixel{
        .r = clamp_channel(parse_double(req, "r", 0.0)),
        .g = clamp_channel(parse_double(req, "g", 0.0)),
        .b = clamp_channel(parse_double(req, "b", 0.0)),
    };
    const Hsv hsv = rgb_to_hsv(pixel);
    Json out;
    out["h"] = hsv.h;
    out["s"] = hsv.s;
    out["v"] = hsv.v;
    return Response::json(out.dump());
}

Response App::handle_hsv_to_rgb(const Request& req) const {
    const Hsv hsv{
        .h = normalize_hue(parse_double(req, "h", 0.0)),
        .s = std::clamp(parse_double(req, "s", 0.0), 0.0, 1.0),
        .v = std::clamp(parse_double(req, "v", 0.0), 0.0, 1.0),
    };
    const Rgb8 rgb = hsv_to_rgb(hsv);
    Json out;
    out["r"] = rgb.r;
    out["g"] = rgb.g;
    out["b"] = rgb.b;
    return Response::json(out.dump());
}

Response App::handle_pixel(const Request& req) const {
    const ImageSize size = image_.size();
    const int x = std::clamp(parse_int(req, "x", 0), 0, size.width - 1);
    const int y = std::clamp(parse_int(req, "y", 0), 0, size.height - 1);
    const Rgb8 pixel = image_.at(x, y);
    const Hsv hsv = rgb_to_hsv(pixel);
    Json out;
    out["r"] = pixel.r;
    out["g"] = pixel.g;
    out["b"] = pixel.b;
    out["h"] = hsv.h;
    out["s"] = hsv.s;
    out["v"] = hsv.v;
    out["width"] = size.width;
    out["height"] = size.height;
    return Response::json(out.dump());
}

HttpServer::Builder register_routes(HttpServer::Builder builder, const App& app,
                                    std::filesystem::path web_root) {
    return std::move(builder)
        .get(
            "/api/image",
            [&app](const Request& req) { return app.handle_source_image(req); })
        .get("/api/intensity",
             [&app](const Request& req) { return app.handle_intensity(req); })
        .get("/api/histogram",
             [&app](const Request& req) { return app.handle_histogram(req); })
        .get("/api/rgb-to-hsv",
             [&app](const Request& req) { return app.handle_rgb_to_hsv(req); })
        .get("/api/hsv-to-rgb",
             [&app](const Request& req) { return app.handle_hsv_to_rgb(req); })
        .get("/api/pixel",
             [&app](const Request& req) { return app.handle_pixel(req); })
        .static_dir("/", std::move(web_root));
}

}  // namespace week3::color
