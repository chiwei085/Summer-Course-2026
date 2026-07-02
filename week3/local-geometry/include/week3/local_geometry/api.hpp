#pragma once

#include <filesystem>

#include "week3/local_geometry/image.hpp"
#include "week3/local_geometry/result.hpp"
#include "week3/local_geometry/server.hpp"

namespace week3::local_geometry
{

struct AppError
{
    std::string message;
};

// Owns the three sample images (one per topic) and knows how to answer
// every route the notebook frontend calls. Kept separate from `HttpServer`
// so the HTTP transport and the image-processing app logic don't leak into
// each other.
class App
{
public:
    static Result<App, AppError> load(std::filesystem::path edges_image_path,
                                      std::filesystem::path corners_image_path,
                                      std::filesystem::path lines_image_path);

    // Shared gradient foundation.
    [[nodiscard]] Response handle_gradient_source(const Request&) const;
    [[nodiscard]] Response handle_gradient_magnitude(const Request&) const;

    // Edge detection.
    [[nodiscard]] Response handle_edges_source(const Request&) const;
    [[nodiscard]] Response handle_edges_canny(const Request&) const;

    // Corner detection.
    [[nodiscard]] Response handle_corners_source(const Request&) const;
    [[nodiscard]] Response handle_corners_detect(const Request&) const;

    // Line detection.
    [[nodiscard]] Response handle_lines_source(const Request&) const;
    [[nodiscard]] Response handle_lines_detect(const Request&) const;

private:
    App(Image edges_image, Image corners_image, Image lines_image)
        : edges_image_{std::move(edges_image)},
          corners_image_{std::move(corners_image)},
          lines_image_{std::move(lines_image)} {}

    Image edges_image_;
    Image corners_image_;
    Image lines_image_;
};

// Wires every `App` handler into a server builder under `/api/...` and
// mounts `web_root` at `/`.
[[nodiscard]] HttpServer::Builder register_routes(
    HttpServer::Builder builder, const App& app,
    std::filesystem::path web_root);

}  // namespace week3::local_geometry
