#pragma once

#include <filesystem>

#include "week3/color/image.hpp"
#include "week3/color/result.hpp"
#include "week3/color/server.hpp"

namespace week3::color
{

struct AppError
{
    std::string message;
};

// Owns the loaded sample image and knows how to answer every route the
// notebook frontend calls. Kept separate from `HttpServer` so the HTTP
// transport and the image-processing app logic don't leak into each other.
class App
{
public:
    static Result<App, AppError> load(std::filesystem::path image_path);

    [[nodiscard]] Response handle_source_image(const Request&) const;
    [[nodiscard]] Response handle_intensity(const Request&) const;
    [[nodiscard]] Response handle_histogram(const Request&) const;
    [[nodiscard]] Response handle_rgb_to_hsv(const Request&) const;
    [[nodiscard]] Response handle_hsv_to_rgb(const Request&) const;
    [[nodiscard]] Response handle_pixel(const Request&) const;

private:
    explicit App(Image image) : image_{std::move(image)} {}

    Image image_;
};

// Wires every `App` handler into a server builder under `/api/...` and
// mounts `web_root` at `/`.
[[nodiscard]] HttpServer::Builder register_routes(
    HttpServer::Builder builder, const App& app,
    std::filesystem::path web_root);

}  // namespace week3::color
