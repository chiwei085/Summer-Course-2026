#pragma once

#include <array>
#include <filesystem>

#include "week3/snake/image.hpp"
#include "week3/snake/result.hpp"
#include "week3/snake/server.hpp"

namespace week3::snake
{

struct AppError
{
    std::string message;
};

// Owns the three fixed sample images and knows how to answer every route
// the notebook frontend calls. Each image's algorithm parameters are a
// `config::ImageConfig` instantiation in config.hpp rather than living here
// -- `App` just looks them up by id.
class App
{
public:
    static Result<App, AppError> load(std::filesystem::path image1_path,
                                      std::filesystem::path image2_path,
                                      std::filesystem::path image3_path);

    // Scaled source image, id in {1, 2, 3}.
    [[nodiscard]] Response handle_source(const Request&) const;

    // Shared foundation: blurred grayscale and Sobel gradient magnitude,
    // rendered as PNGs.
    [[nodiscard]] Response handle_grayscale(const Request&) const;
    [[nodiscard]] Response handle_gradient(const Request&) const;

    // The per-image default snake/initial-contour parameters, so the
    // frontend can initialize its sliders from the same config headers the
    // backend uses.
    [[nodiscard]] Response handle_defaults(const Request&) const;

    // The automatically-found initial contour (Otsu + connected components
    // + ellipse fit), independent of any snake parameters.
    [[nodiscard]] Response handle_init(const Request&) const;

    // Runs the greedy snake from the initial contour and returns every
    // intermediate contour shape so the frontend can animate convergence.
    [[nodiscard]] Response handle_run(const Request&) const;

private:
    explicit App(std::array<Image, 3> images) : images_{std::move(images)} {}

    std::array<Image, 3> images_;
};

// Wires every `App` handler into a server builder under `/api/...` and
// mounts `web_root` at `/`.
[[nodiscard]] HttpServer::Builder register_routes(
    HttpServer::Builder builder, const App& app,
    std::filesystem::path web_root);

}  // namespace week3::snake
