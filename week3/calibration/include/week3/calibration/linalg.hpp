#pragma once

#include <week3/calibration/result.hpp>

#include <array>
#include <cmath>
#include <concepts>
#include <cstddef>
#include <vector>

namespace week3::linalg
{

struct Vec2
{
    double x{0.0};
    double y{0.0};
};

struct Vec3
{
    double x{0.0};
    double y{0.0};
    double z{0.0};
};

struct Mat3
{
    std::array<double, 9> values{};

    [[nodiscard]] constexpr double& operator()(std::size_t row,
                                               std::size_t col) {
        return values[row * 3 + col];
    }

    [[nodiscard]] constexpr double operator()(std::size_t row,
                                              std::size_t col) const {
        return values[row * 3 + col];
    }
};

struct Matrix
{
    std::size_t rows{0};
    std::size_t cols{0};
    std::vector<double> values;

    [[nodiscard]] static Matrix zero(std::size_t row_count,
                                     std::size_t col_count) {
        return {
            .rows = row_count,
            .cols = col_count,
            .values = std::vector<double>(row_count * col_count, 0.0),
        };
    }

    [[nodiscard]] double& operator()(std::size_t row, std::size_t col) {
        return values[row * cols + col];
    }

    [[nodiscard]] double operator()(std::size_t row, std::size_t col) const {
        return values[row * cols + col];
    }
};

template <class T>
concept MatrixLike =
    requires(T matrix, const T const_matrix, std::size_t row, std::size_t col) {
        { const_matrix.rows } -> std::convertible_to<std::size_t>;
        { const_matrix.cols } -> std::convertible_to<std::size_t>;
        { matrix(row, col) } -> std::same_as<double&>;
        { const_matrix(row, col) } -> std::convertible_to<double>;
    };

[[nodiscard]] constexpr Vec3 operator+(Vec3 lhs, Vec3 rhs) {
    return {.x = lhs.x + rhs.x, .y = lhs.y + rhs.y, .z = lhs.z + rhs.z};
}

[[nodiscard]] constexpr Vec3 operator-(Vec3 lhs, Vec3 rhs) {
    return {.x = lhs.x - rhs.x, .y = lhs.y - rhs.y, .z = lhs.z - rhs.z};
}

[[nodiscard]] constexpr Vec3 operator*(double scalar, Vec3 value) {
    return {
        .x = scalar * value.x, .y = scalar * value.y, .z = scalar * value.z};
}

[[nodiscard]] constexpr Vec3 operator/(Vec3 value, double scalar) {
    return {
        .x = value.x / scalar, .y = value.y / scalar, .z = value.z / scalar};
}

[[nodiscard]] constexpr double dot(Vec3 lhs, Vec3 rhs) {
    return lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z;
}

[[nodiscard]] constexpr Vec3 cross(Vec3 lhs, Vec3 rhs) {
    return {
        .x = lhs.y * rhs.z - lhs.z * rhs.y,
        .y = lhs.z * rhs.x - lhs.x * rhs.z,
        .z = lhs.x * rhs.y - lhs.y * rhs.x,
    };
}

[[nodiscard]] inline double norm(Vec3 value) {
    return std::sqrt(dot(value, value));
}

[[nodiscard]] inline Vec3 normalized(Vec3 value) {
    return value / norm(value);
}

[[nodiscard]] constexpr Mat3 identity3() {
    Mat3 out{};
    out(0, 0) = 1.0;
    out(1, 1) = 1.0;
    out(2, 2) = 1.0;
    return out;
}

[[nodiscard]] inline bool nearly_zero(double value, double epsilon = 1e-12) {
    return std::abs(value) < epsilon;
}

[[nodiscard]] constexpr Vec3 column(const Mat3& matrix, std::size_t col) {
    return {.x = matrix(0, col), .y = matrix(1, col), .z = matrix(2, col)};
}

constexpr void set_column(Mat3& matrix, std::size_t col, Vec3 value) {
    matrix(0, col) = value.x;
    matrix(1, col) = value.y;
    matrix(2, col) = value.z;
}

[[nodiscard]] constexpr Vec3 operator*(const Mat3& matrix, Vec3 value) {
    return {
        .x = matrix(0, 0) * value.x + matrix(0, 1) * value.y +
             matrix(0, 2) * value.z,
        .y = matrix(1, 0) * value.x + matrix(1, 1) * value.y +
             matrix(1, 2) * value.z,
        .z = matrix(2, 0) * value.x + matrix(2, 1) * value.y +
             matrix(2, 2) * value.z,
    };
}

[[nodiscard]] constexpr Mat3 operator*(const Mat3& lhs, const Mat3& rhs) {
    Mat3 out{};
    for (std::size_t row = 0; row < 3; ++row) {
        for (std::size_t col = 0; col < 3; ++col) {
            for (std::size_t k = 0; k < 3; ++k) {
                out(row, col) += lhs(row, k) * rhs(k, col);
            }
        }
    }
    return out;
}

[[nodiscard]] constexpr Mat3 inverse(const Mat3& matrix) {
    const double a = matrix(0, 0);
    const double b = matrix(0, 1);
    const double c = matrix(0, 2);
    const double d = matrix(1, 0);
    const double e = matrix(1, 1);
    const double f = matrix(1, 2);
    const double g = matrix(2, 0);
    const double h = matrix(2, 1);
    const double i = matrix(2, 2);

    const double det =
        a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);

    Mat3 out{};
    out(0, 0) = (e * i - f * h) / det;
    out(0, 1) = (c * h - b * i) / det;
    out(0, 2) = (b * f - c * e) / det;
    out(1, 0) = (f * g - d * i) / det;
    out(1, 1) = (a * i - c * g) / det;
    out(1, 2) = (c * d - a * f) / det;
    out(2, 0) = (d * h - e * g) / det;
    out(2, 1) = (b * g - a * h) / det;
    out(2, 2) = (a * e - b * d) / det;
    return out;
}

template <MatrixLike T>
[[nodiscard]] Matrix transpose_multiply_self(const T& matrix) {
    auto out = Matrix::zero(matrix.cols, matrix.cols);
    for (std::size_t row = 0; row < matrix.rows; ++row) {
        for (std::size_t i = 0; i < matrix.cols; ++i) {
            for (std::size_t j = i; j < matrix.cols; ++j) {
                out(i, j) += matrix(row, i) * matrix(row, j);
            }
        }
    }
    for (std::size_t i = 0; i < matrix.cols; ++i) {
        for (std::size_t j = 0; j < i; ++j) {
            out(i, j) = out(j, i);
        }
    }
    return out;
}

[[nodiscard]] Result<std::vector<double>, Error> smallest_eigenvector_symmetric(
    Matrix matrix);

// Solves the symmetric positive-definite system `a * x = b` via Cholesky
// decomposition. Intended for normal-equation solves (e.g. J^T J x = J^T r
// in a Levenberg-Marquardt step), where `a` is guaranteed SPD by
// construction (a damped Gram matrix).
[[nodiscard]] Result<std::vector<double>, Error> solve_spd(
    Matrix a, std::vector<double> b);

}  // namespace week3::linalg
