from conan import ConanFile
from conan.tools.cmake import CMakeToolchain


class Week4BasicConan(ConanFile):
    settings = "os", "compiler", "build_type", "arch"
    generators = "CMakeDeps"
    requires = "sophus/1.22.10", "eigen/3.4.0"

    def generate(self):
        toolchain = CMakeToolchain(self)
        toolchain.generator = "Ninja"
        toolchain.user_presets_path = False
        toolchain.generate()
