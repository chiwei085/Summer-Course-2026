#pragma once

#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace rik_asio
{

enum class io_status
{
    ok,
    would_block,
    closed,
    error,
};

struct io_result
{
    io_status status = io_status::ok;
    std::size_t bytes = 0;
    int error = 0;

    [[nodiscard]] bool ok() const { return status == io_status::ok; }
    [[nodiscard]] bool would_block() const {
        return status == io_status::would_block;
    }
};

class socket_error : public std::runtime_error
{
public:
    explicit socket_error(std::string message)
        : std::runtime_error(std::move(message)) {}
};

struct endpoint
{
    sockaddr_storage address{};
    socklen_t length = 0;
};

namespace detail
{

inline bool is_would_block(int error) {
    return error == EWOULDBLOCK || error == EAGAIN;
}

inline io_result result_from_errno() {
    const int error = errno;
    if (is_would_block(error)) {
        return {io_status::would_block, 0, error};
    }
    return {io_status::error, 0, error};
}

inline void throw_errno(std::string_view operation) {
    throw socket_error(std::string(operation) + ": " + std::strerror(errno));
}

class addrinfo_list
{
public:
    explicit addrinfo_list(addrinfo* head) : head_(head) {}
    addrinfo_list(const addrinfo_list&) = delete;
    addrinfo_list& operator=(const addrinfo_list&) = delete;
    ~addrinfo_list() {
        if (head_ != nullptr) {
            freeaddrinfo(head_);
        }
    }

    [[nodiscard]] addrinfo* get() const { return head_; }

private:
    addrinfo* head_ = nullptr;
};

inline addrinfo_list resolve(std::string_view host, std::string_view service,
                             int socket_type, int flags = 0) {
    addrinfo hints{};
    hints.ai_family = AF_INET;
    hints.ai_socktype = socket_type;
    hints.ai_flags = flags;

    addrinfo* raw = nullptr;
    const std::string host_text(host);
    const std::string service_text(service);
    const char* host_ptr = host_text.empty() ? nullptr : host_text.c_str();
    const int rc = getaddrinfo(host_ptr, service_text.c_str(), &hints, &raw);
    if (rc != 0) {
        throw socket_error("resolve: " + std::string(gai_strerror(rc)));
    }
    return addrinfo_list(raw);
}

inline endpoint to_endpoint(const addrinfo& info) {
    endpoint out;
    if (info.ai_addrlen > sizeof(out.address)) {
        throw socket_error("resolved address is too large");
    }
    std::memcpy(&out.address, info.ai_addr, info.ai_addrlen);
    out.length = static_cast<socklen_t>(info.ai_addrlen);
    return out;
}

}  // namespace detail

inline endpoint resolve_udp(std::string_view host, std::string_view service) {
    const auto list = detail::resolve(host, service, SOCK_DGRAM);
    return detail::to_endpoint(*list.get());
}

class socket_handle
{
public:
    socket_handle() = default;
    explicit socket_handle(int fd) : fd_(fd) {}
    socket_handle(const socket_handle&) = delete;
    socket_handle& operator=(const socket_handle&) = delete;

    socket_handle(socket_handle&& other) noexcept
        : fd_(std::exchange(other.fd_, -1)) {}

    socket_handle& operator=(socket_handle&& other) noexcept {
        if (this != &other) {
            close();
            fd_ = std::exchange(other.fd_, -1);
        }
        return *this;
    }

    ~socket_handle() { close(); }

    [[nodiscard]] int fd() const { return fd_; }
    [[nodiscard]] bool valid() const { return fd_ >= 0; }

    void close() {
        if (fd_ >= 0) {
            ::close(fd_);
            fd_ = -1;
        }
    }

    void set_non_blocking(bool enabled) {
        const int current = fcntl(fd_, F_GETFL, 0);
        if (current < 0) {
            detail::throw_errno("fcntl(F_GETFL)");
        }
        const int next =
            enabled ? (current | O_NONBLOCK) : (current & ~O_NONBLOCK);
        if (fcntl(fd_, F_SETFL, next) < 0) {
            detail::throw_errno("fcntl(F_SETFL)");
        }
    }

protected:
    int fd_ = -1;
};

class udp_socket : public socket_handle
{
public:
    udp_socket() = default;
    explicit udp_socket(int fd) : socket_handle(fd) {}

    static udp_socket open() {
        int fd = ::socket(AF_INET, SOCK_DGRAM, 0);
        if (fd < 0) {
            detail::throw_errno("udp socket");
        }
        return udp_socket(fd);
    }

    static udp_socket bind_any(int port) {
        udp_socket socket = open();
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_ANY);
        address.sin_port = htons(static_cast<std::uint16_t>(port));
        if (::bind(socket.fd(), reinterpret_cast<sockaddr*>(&address),
                   sizeof(address)) < 0) {
            detail::throw_errno("udp bind");
        }
        return socket;
    }

    template <class Byte>
    io_result receive_from(std::span<Byte> buffer, endpoint& sender) {
        static_assert(sizeof(Byte) == 1);
        sender.length = sizeof(sender.address);
        const ssize_t n = ::recvfrom(
            fd_, buffer.data(), buffer.size(), 0,
            reinterpret_cast<sockaddr*>(&sender.address), &sender.length);
        if (n > 0) {
            return {io_status::ok, static_cast<std::size_t>(n), 0};
        }
        if (n == 0) {
            return {io_status::closed, 0, 0};
        }
        return detail::result_from_errno();
    }

    io_result send_to(std::span<const std::uint8_t> buffer,
                      const endpoint& target) {
        const ssize_t n = ::sendto(
            fd_, buffer.data(), buffer.size(), 0,
            reinterpret_cast<const sockaddr*>(&target.address), target.length);
        if (n >= 0) {
            return {io_status::ok, static_cast<std::size_t>(n), 0};
        }
        return detail::result_from_errno();
    }

    io_result send_to(std::string_view buffer, const endpoint& target) {
        auto* data = reinterpret_cast<const std::uint8_t*>(buffer.data());
        return send_to(std::span<const std::uint8_t>(data, buffer.size()),
                       target);
    }
};

class tcp_socket : public socket_handle
{
public:
    tcp_socket() = default;
    explicit tcp_socket(int fd) : socket_handle(fd) {}

    static tcp_socket connect(std::string_view host, std::string_view service) {
        const auto list = detail::resolve(host, service, SOCK_STREAM);
        for (auto* info = list.get(); info != nullptr; info = info->ai_next) {
            int fd =
                ::socket(info->ai_family, info->ai_socktype, info->ai_protocol);
            if (fd < 0) {
                continue;
            }
            if (::connect(fd, info->ai_addr, info->ai_addrlen) == 0) {
                return tcp_socket(fd);
            }
            ::close(fd);
        }
        throw socket_error("tcp connect failed");
    }

    template <class Byte>
    io_result read_some(std::span<Byte> buffer) {
        static_assert(sizeof(Byte) == 1);
        const ssize_t n = ::recv(fd_, buffer.data(), buffer.size(), 0);
        if (n > 0) {
            return {io_status::ok, static_cast<std::size_t>(n), 0};
        }
        if (n == 0) {
            return {io_status::closed, 0, 0};
        }
        return detail::result_from_errno();
    }

    template <class Byte>
    void read_exact(std::span<Byte> buffer) {
        static_assert(sizeof(Byte) == 1);
        std::size_t offset = 0;
        while (offset < buffer.size()) {
            auto result = read_some(buffer.subspan(offset));
            if (result.status == io_status::closed) {
                throw socket_error("tcp read closed");
            }
            if (result.status == io_status::would_block) {
                continue;
            }
            if (!result.ok()) {
                throw socket_error("tcp read failed: " +
                                   std::to_string(result.error));
            }
            offset += result.bytes;
        }
    }

    void write_all(std::span<const std::uint8_t> buffer) {
        std::size_t offset = 0;
        while (offset < buffer.size()) {
            int flags = 0;
#ifdef MSG_NOSIGNAL
            flags = MSG_NOSIGNAL;
#endif
            const ssize_t n = ::send(fd_, buffer.data() + offset,
                                     buffer.size() - offset, flags);
            if (n > 0) {
                offset += static_cast<std::size_t>(n);
                continue;
            }
            if (n < 0 && detail::is_would_block(errno)) {
                continue;
            }
            if (n < 0) {
                detail::throw_errno("tcp write");
            }
            throw socket_error("tcp write closed");
        }
    }

    void write_all(std::string_view buffer) {
        auto* data = reinterpret_cast<const std::uint8_t*>(buffer.data());
        write_all(std::span<const std::uint8_t>(data, buffer.size()));
    }
};

struct accept_result
{
    io_status status = io_status::ok;
    tcp_socket socket;
    int error = 0;

    [[nodiscard]] bool ok() const { return status == io_status::ok; }
    [[nodiscard]] bool would_block() const {
        return status == io_status::would_block;
    }
};

class tcp_acceptor : public socket_handle
{
public:
    tcp_acceptor() = default;
    explicit tcp_acceptor(int fd) : socket_handle(fd) {}

    static tcp_acceptor bind_any(int port) {
        int fd = ::socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) {
            detail::throw_errno("tcp socket");
        }

        int reuse = 1;
        if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) <
            0) {
            ::close(fd);
            detail::throw_errno("setsockopt(SO_REUSEADDR)");
        }

        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_ANY);
        address.sin_port = htons(static_cast<std::uint16_t>(port));
        if (::bind(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) <
            0) {
            ::close(fd);
            detail::throw_errno("tcp bind");
        }
        if (::listen(fd, SOMAXCONN) < 0) {
            ::close(fd);
            detail::throw_errno("tcp listen");
        }
        return tcp_acceptor(fd);
    }

    accept_result accept() {
        int client = ::accept(fd_, nullptr, nullptr);
        if (client >= 0) {
            return {io_status::ok, tcp_socket(client), 0};
        }
        const int error = errno;
        if (detail::is_would_block(error)) {
            return {io_status::would_block, tcp_socket(), error};
        }
        return {io_status::error, tcp_socket(), error};
    }
};

}  // namespace rik_asio
