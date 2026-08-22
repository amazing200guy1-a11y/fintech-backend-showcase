cmake_minimum_required(VERSION 3.20)
project(MehdQuantEngine VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Compiler optimization flags
if(MSVC)
    add_compile_options(/O2 /arch:AVX2 /W4)
else()
    add_compile_options(-O3 -mavx2 -Wall -Wextra -Wpedantic)
endif()

include_directories(include)

add_library(mehd_quant_core STATIC
    src/fast_risk_kernel.cpp
    src/asymmetric_pricing.cpp
)

target_include_directories(mehd_quant_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)
