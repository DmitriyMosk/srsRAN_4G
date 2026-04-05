cmake_minimum_required(VERSION 3.16)

project(ltemon LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

get_filename_component(LTEMON_SOURCE_ROOT "${CMAKE_CURRENT_LIST_DIR}" ABSOLUTE)
get_filename_component(FPGA_BUILDROOT_ROOT "${LTEMON_SOURCE_ROOT}/../.." ABSOLUTE)

set(LTEMON_PREFIX_HINTS
    "${FPGA_BUILDROOT_ROOT}/buildroot/prefix"
)

if(CMAKE_SYSROOT)
    list(APPEND LTEMON_PREFIX_HINTS
        "${CMAKE_SYSROOT}/usr"
        "${CMAKE_SYSROOT}/usr/local"
    )
endif()

foreach(_prefix IN LISTS LTEMON_PREFIX_HINTS)
    if(EXISTS "${_prefix}")
        list(APPEND CMAKE_PREFIX_PATH "${_prefix}")
    endif()
endforeach()

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(LIBMETAL QUIET IMPORTED_TARGET libmetal)
endif()

file(GLOB_RECURSE LTEMON_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_LIST_DIR}/src/*.c"
)

if(NOT LTEMON_SOURCES)
    message(FATAL_ERROR "No C sources found under ${CMAKE_CURRENT_LIST_DIR}/src")
endif()

add_executable(ltemon ${LTEMON_SOURCES})

target_include_directories(ltemon PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/src"
)

target_compile_options(ltemon PRIVATE
    -Wall
    -Wextra
    -Wpedantic
)

if(TARGET PkgConfig::LIBMETAL)
    target_link_libraries(ltemon PRIVATE PkgConfig::LIBMETAL)
else()
    set(_LIBMETAL_INCLUDE_HINTS "")
    set(_LIBMETAL_LIBRARY_HINTS "")

    foreach(_prefix IN LISTS LTEMON_PREFIX_HINTS)
        list(APPEND _LIBMETAL_INCLUDE_HINTS
            "${_prefix}/include"
        )
        list(APPEND _LIBMETAL_LIBRARY_HINTS
            "${_prefix}/lib"
            "${_prefix}/lib/arm-linux-gnueabihf"
        )
    endforeach()

    find_path(METAL_INCLUDE_DIR
        NAMES metal/init.h
        HINTS ${_LIBMETAL_INCLUDE_HINTS}
    )

    find_library(METAL_LIBRARY
        NAMES metal
        HINTS ${_LIBMETAL_LIBRARY_HINTS}
    )

    if(NOT METAL_INCLUDE_DIR)
        message(FATAL_ERROR
            "libmetal headers not found.\n"
            "Checked prefixes:\n"
            "  ${LTEMON_PREFIX_HINTS}\n"
            "Expected: <prefix>/include/metal/init.h"
        )
    endif()

    if(NOT METAL_LIBRARY)
        message(FATAL_ERROR
            "libmetal library not found.\n"
            "Checked prefixes:\n"
            "  ${LTEMON_PREFIX_HINTS}\n"
            "Expected: <prefix>/lib/libmetal.a or libmetal.so"
        )
    endif()

    add_library(libmetal::metal UNKNOWN IMPORTED)
    set_target_properties(libmetal::metal PROPERTIES
        IMPORTED_LOCATION "${METAL_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${METAL_INCLUDE_DIR}"
    )

    target_link_libraries(ltemon PRIVATE libmetal::metal)
endif()
