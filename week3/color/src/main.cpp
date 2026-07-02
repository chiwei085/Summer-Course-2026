#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

#include "week3/color/api.hpp"
#include "week3/color/server.hpp"

namespace
{

week3::color::HttpServer* g_server = nullptr;

void handle_sigint(int) {
    if (g_server) g_server->stop();
}

}  // namespace

int main(int argc, char** argv) {
    const std::filesystem::path exe_dir =
        std::filesystem::absolute(argv[0]).parent_path();
    const std::filesystem::path project_root = exe_dir.parent_path();

    std::filesystem::path image_path =
        argc > 1 ? std::filesystem::path{argv[1]}
                 : project_root / "images" / "mortis.png";
    std::string listen_address = argc > 2 ? argv[2] : "http://0.0.0.0:8080";

    auto app_result = week3::color::App::load(image_path);
    if (app_result.is_err()) {
        std::fprintf(stderr, "failed to load sample image %s: %s\n",
                     image_path.string().c_str(),
                     app_result.error().message.c_str());
        return EXIT_FAILURE;
    }

    auto server_result =
        week3::color::register_routes(
            week3::color::HttpServer::builder().listen_address(listen_address),
            app_result.value(), project_root / "web")
            .build();
    if (server_result.is_err()) {
        std::fprintf(stderr, "failed to start server: %s\n",
                     server_result.error().message.c_str());
        return EXIT_FAILURE;
    }

    week3::color::HttpServer server = std::move(server_result.value());
    g_server = &server;
    std::signal(SIGINT, handle_sigint);

    std::printf("week3 color notebook listening on %s\n",
                server.listen_address().c_str());
    std::printf("open %s in a browser\n", server.listen_address().c_str());
    server.run();
    return EXIT_SUCCESS;
}
