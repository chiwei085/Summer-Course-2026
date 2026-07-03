#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

#include "week3/snake/api.hpp"
#include "week3/snake/config.hpp"
#include "week3/snake/server.hpp"

namespace
{

week3::snake::HttpServer* g_server = nullptr;

void handle_sigint(int) {
    if (g_server) g_server->stop();
}

}  // namespace

int main(int argc, char** argv) {
    const std::filesystem::path exe_dir =
        std::filesystem::absolute(argv[0]).parent_path();
    const std::filesystem::path project_root = exe_dir.parent_path();

    const std::filesystem::path image1_path =
        project_root / week3::snake::config::kImage1Path;
    const std::filesystem::path image2_path =
        project_root / week3::snake::config::kImage2Path;
    const std::filesystem::path image3_path =
        project_root / week3::snake::config::kImage3Path;
    std::string listen_address = argc > 1 ? argv[1] : "http://0.0.0.0:8080";

    auto app_result =
        week3::snake::App::load(image1_path, image2_path, image3_path);
    if (app_result.is_err()) {
        std::fprintf(stderr, "failed to load sample images: %s\n",
                     app_result.error().message.c_str());
        return EXIT_FAILURE;
    }

    auto server_result =
        week3::snake::register_routes(
            week3::snake::HttpServer::builder().listen_address(listen_address),
            app_result.value(), project_root / "web")
            .build();
    if (server_result.is_err()) {
        std::fprintf(stderr, "failed to start server: %s\n",
                     server_result.error().message.c_str());
        return EXIT_FAILURE;
    }

    week3::snake::HttpServer server = std::move(server_result.value());
    g_server = &server;
    std::signal(SIGINT, handle_sigint);

    std::printf("week3 snake homework notebook listening on %s\n",
                server.listen_address().c_str());
    std::printf("open %s in a browser\n", server.listen_address().c_str());
    server.run();
    return EXIT_SUCCESS;
}
