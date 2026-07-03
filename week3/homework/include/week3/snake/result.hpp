#pragma once

#include <optional>
#include <string>
#include <utility>
#include <variant>

namespace week3::snake
{

// A Rust-flavored `Result<T, E>`: a value is either `Ok(T)` or `Err(E)`,
// never both, and callers must check which before extracting it.
template <class T, class E>
class Result
{
public:
    static Result ok(T value) {
        return Result{std::in_place_index<0>, std::move(value)};
    }
    static Result err(E error) {
        return Result{std::in_place_index<1>, std::move(error)};
    }

    [[nodiscard]] bool is_ok() const { return data_.index() == 0; }
    [[nodiscard]] bool is_err() const { return data_.index() == 1; }
    explicit operator bool() const { return is_ok(); }

    [[nodiscard]] T& value() { return std::get<0>(data_); }
    [[nodiscard]] const T& value() const { return std::get<0>(data_); }
    [[nodiscard]] T value_or(T fallback) const {
        return is_ok() ? std::get<0>(data_) : std::move(fallback);
    }

    [[nodiscard]] E& error() { return std::get<1>(data_); }
    [[nodiscard]] const E& error() const { return std::get<1>(data_); }

private:
    Result(std::in_place_index_t<0> tag, T value)
        : data_{tag, std::move(value)} {}
    Result(std::in_place_index_t<1> tag, E error)
        : data_{tag, std::move(error)} {}

    std::variant<T, E> data_;
};

// A Rust-flavored `Option<T>`, spelled out for readability at call sites
// that would otherwise read as a bare `std::optional`.
template <class T>
using Option = std::optional<T>;

struct Error
{
    std::string message;
};

}  // namespace week3::snake
