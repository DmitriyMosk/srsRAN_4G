cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED CMAKE_C_COMPILER AND DEFINED ENV{CC} AND NOT "$ENV{CC}" STREQUAL "")
    set(CMAKE_C_COMPILER "$ENV{CC}" CACHE FILEPATH "C compiler from CC environment")
endif()

project(ltemon LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
option(LTEMON_FORCE_ARMHF_RELEASE_FLAGS "Force Cortex-A9/armhf release tuning" OFF)

if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    Debug
    Release
    RelWithDebInfo
    MinSizeRel
)

message(STATUS "C compiler: ${CMAKE_C_COMPILER}")
if(CMAKE_CONFIGURATION_TYPES)
    message(STATUS "Configurations: ${CMAKE_CONFIGURATION_TYPES}")
else()
    message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
endif()

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(LIBMETAL QUIET IMPORTED_TARGET libmetal)
endif()

set(LTEMON_PREFIX_HINTS "")
if(DEFINED ENV{LIBMETAL_ROOT} AND NOT "$ENV{LIBMETAL_ROOT}" STREQUAL "")
    list(APPEND LTEMON_PREFIX_HINTS "$ENV{LIBMETAL_ROOT}")
endif()

if(CMAKE_SYSROOT)
    list(APPEND LTEMON_PREFIX_HINTS
        "${CMAKE_SYSROOT}/usr"
        "${CMAKE_SYSROOT}/usr/local"
    )
endif()

file(GLOB_RECURSE LTEMON_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c"
)

if(NOT LTEMON_SOURCES)
    message(FATAL_ERROR "No C sources found under ${CMAKE_CURRENT_SOURCE_DIR}/src")
endif()

file(GLOB LTEMON_SOURCE_DIRS LIST_DIRECTORIES true
    "${CMAKE_CURRENT_SOURCE_DIR}/src/*"
)

set(LTEMON_INCLUDE_DIRS
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

foreach(_dir IN LISTS LTEMON_SOURCE_DIRS)
    if(IS_DIRECTORY "${_dir}")
        list(APPEND LTEMON_INCLUDE_DIRS "${_dir}")
    endif()
endforeach()

add_executable(ltemon ${LTEMON_SOURCES})

target_include_directories(ltemon PRIVATE ${LTEMON_INCLUDE_DIRS})

string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" LTEMON_SYSTEM_PROCESSOR_LOWER)
string(TOLOWER "${CMAKE_LIBRARY_ARCHITECTURE}" LTEMON_LIBRARY_ARCH_LOWER)
string(TOLOWER "${CMAKE_C_COMPILER_TARGET}" LTEMON_COMPILER_TARGET_LOWER)
string(TOLOWER "${CMAKE_C_COMPILER}" LTEMON_COMPILER_LOWER)

set(LTEMON_IS_ARMHF FALSE)
if(LTEMON_SYSTEM_PROCESSOR_LOWER MATCHES "^arm(v7.*|hf)?$" OR
   LTEMON_LIBRARY_ARCH_LOWER MATCHES "arm.*gnueabihf" OR
   LTEMON_COMPILER_TARGET_LOWER MATCHES "arm.*gnueabihf" OR
   LTEMON_COMPILER_LOWER MATCHES "arm-linux-gnueabihf")
    set(LTEMON_IS_ARMHF TRUE)
endif()

if(LTEMON_FORCE_ARMHF_RELEASE_FLAGS)
    set(LTEMON_IS_ARMHF TRUE)
endif()

message(STATUS "armhf release tuning: ${LTEMON_IS_ARMHF}")

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(ltemon PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        $<$<CONFIG:Debug>:-O0;-g3;-fno-omit-frame-pointer>
        $<$<CONFIG:Release>:-O3;-DNDEBUG>
    )

    if(LTEMON_IS_ARMHF)
        target_compile_options(ltemon PRIVATE
            $<$<CONFIG:Release>:-mcpu=cortex-a9;-mfpu=neon;-mfloat-abi=hard;-ftree-vectorize>
        )
    endif()

    target_link_options(ltemon PRIVATE
        $<$<CONFIG:Release>:-Wl,--gc-sections>
    )
endif()

include(CheckIPOSupported)
check_ipo_supported(RESULT LTEMON_IPO_SUPPORTED OUTPUT LTEMON_IPO_OUTPUT)
if(LTEMON_IPO_SUPPORTED)
    set_property(TARGET ltemon PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
else()
    message(STATUS "IPO/LTO is not available: ${LTEMON_IPO_OUTPUT}")
endif()

# if(TARGET PkgConfig::LIBMETAL)
#     target_link_libraries(ltemon PRIVATE PkgConfig::LIBMETAL)
# else()
#     find_path(METAL_INCLUDE_DIR
#         NAMES metal/init.h
#         PATH_SUFFIXES include
#         HINTS ${LTEMON_PREFIX_HINTS}
#     )

#     find_library(METAL_LIBRARY
#         NAMES metal
#         PATH_SUFFIXES lib lib64 lib/arm-linux-gnueabihf
#         HINTS ${LTEMON_PREFIX_HINTS}
#     )

#     if(NOT METAL_INCLUDE_DIR)
#         message(FATAL_ERROR
#             "libmetal headers not found. "
#             "Install libmetal or point CMake to it via CMAKE_PREFIX_PATH / CMAKE_SYSROOT / LIBMETAL_ROOT."
#         )
#     endif()

#     if(NOT METAL_LIBRARY)
#         message(FATAL_ERROR
#             "libmetal library not found. "
#             "Install libmetal or point CMake to it via CMAKE_PREFIX_PATH / CMAKE_SYSROOT / LIBMETAL_ROOT."
#         )
#     endif()

#     add_library(libmetal::metal UNKNOWN IMPORTED)
#     set_target_properties(libmetal::metal PROPERTIES
#         IMPORTED_LOCATION "${METAL_LIBRARY}"
#         INTERFACE_INCLUDE_DIRECTORIES "${METAL_INCLUDE_DIR}"
#     )

#     target_link_libraries(ltemon PRIVATE libmetal::metal)
# endif()
