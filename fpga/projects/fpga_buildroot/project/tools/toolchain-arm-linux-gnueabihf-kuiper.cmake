set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

get_filename_component(_TOOLS_DIR "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
get_filename_component(FPGA_BUILDROOT_ROOT "${_TOOLS_DIR}/.." ABSOLUTE)

function(_pick_program OUT_VAR)
    foreach(_cand IN LISTS ARGN)
        if(IS_ABSOLUTE "${_cand}")
            if(EXISTS "${_cand}")
                set(${OUT_VAR} "${_cand}" PARENT_SCOPE)
                return()
            endif()
        else()
            find_program(_found_program NAMES "${_cand}")
            if(_found_program)
                set(${OUT_VAR} "${_found_program}" PARENT_SCOPE)
                return()
            endif()
        endif()
    endforeach()
    set(${OUT_VAR} "" PARENT_SCOPE)
endfunction()

set(_C_COMPILER_CANDIDATES
    "${FPGA_BUILDROOT_ROOT}/buildroot/output/host/bin/arm-buildroot-linux-gnueabihf-gcc"
    "${FPGA_BUILDROOT_ROOT}/buildroot/output/host/bin/arm-linux-gnueabihf-gcc"
    arm-linux-gnueabihf-gcc
)

set(_CXX_COMPILER_CANDIDATES
    "${FPGA_BUILDROOT_ROOT}/buildroot/output/host/bin/arm-buildroot-linux-gnueabihf-g++"
    "${FPGA_BUILDROOT_ROOT}/buildroot/output/host/bin/arm-linux-gnueabihf-g++"
    arm-linux-gnueabihf-g++
)

_pick_program(_SELECTED_C_COMPILER ${_C_COMPILER_CANDIDATES})
_pick_program(_SELECTED_CXX_COMPILER ${_CXX_COMPILER_CANDIDATES})

if(NOT _SELECTED_C_COMPILER)
    message(FATAL_ERROR
        "No ARM cross C compiler found.\n"
        "Expected one of:\n"
        "  ${_C_COMPILER_CANDIDATES}\n"
        "Mount buildroot SDK under /workspace/buildroot or install arm-linux-gnueabihf-gcc in the container."
    )
endif()

if(NOT _SELECTED_CXX_COMPILER)
    message(FATAL_ERROR
        "No ARM cross C++ compiler found.\n"
        "Expected one of:\n"
        "  ${_CXX_COMPILER_CANDIDATES}\n"
        "Mount buildroot SDK under /workspace/buildroot or install arm-linux-gnueabihf-g++ in the container."
    )
endif()

set(CMAKE_C_COMPILER   "${_SELECTED_C_COMPILER}"   CACHE FILEPATH "ARM cross C compiler" FORCE)
set(CMAKE_CXX_COMPILER "${_SELECTED_CXX_COMPILER}" CACHE FILEPATH "ARM cross C++ compiler" FORCE)

set(_SYSROOT_CANDIDATES
    "${FPGA_BUILDROOT_ROOT}/buildroot/sysroot"
    "${FPGA_BUILDROOT_ROOT}/buildroot/output/staging"
    "${FPGA_BUILDROOT_ROOT}/buildroot/output/host/arm-buildroot-linux-gnueabihf/sysroot"
    "${FPGA_BUILDROOT_ROOT}/buildroot/output/host/arm-linux-gnueabihf/sysroot"
)

set(_SELECTED_SYSROOT "")
foreach(_candidate IN LISTS _SYSROOT_CANDIDATES)
    if(EXISTS "${_candidate}")
        set(_SELECTED_SYSROOT "${_candidate}")
        break()
    endif()
endforeach()

if(_SELECTED_SYSROOT)
    set(CMAKE_SYSROOT "${_SELECTED_SYSROOT}" CACHE PATH "Target sysroot" FORCE)
endif()

set(_CUSTOM_PREFIX "${FPGA_BUILDROOT_ROOT}/buildroot/prefix")

set(CMAKE_FIND_ROOT_PATH "")
if(CMAKE_SYSROOT)
    list(APPEND CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}")
endif()
if(EXISTS "${_CUSTOM_PREFIX}")
    list(APPEND CMAKE_FIND_ROOT_PATH "${_CUSTOM_PREFIX}")
endif()

if(CMAKE_SYSROOT)
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
else()
    # Fallback mode when only distro cross-toolchain is available.
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
endif()

set(CMAKE_C_FLAGS_INIT   "-mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard")
set(CMAKE_CXX_FLAGS_INIT "-mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard")
set(CMAKE_EXE_LINKER_FLAGS_INIT "")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "")

# Help pkg-config resolve target packages without any command-line flags.
if(CMAKE_SYSROOT)
    set(ENV{PKG_CONFIG_SYSROOT_DIR} "${CMAKE_SYSROOT}")
    set(ENV{PKG_CONFIG_DIR} "")
endif()

set(_PKGCONFIG_DIRS "")
foreach(_dir
    "${_CUSTOM_PREFIX}/lib/pkgconfig"
    "${_CUSTOM_PREFIX}/lib/arm-linux-gnueabihf/pkgconfig"
    "${CMAKE_SYSROOT}/usr/lib/pkgconfig"
    "${CMAKE_SYSROOT}/usr/lib/arm-linux-gnueabihf/pkgconfig"
    "${CMAKE_SYSROOT}/usr/local/lib/pkgconfig"
    "${CMAKE_SYSROOT}/usr/local/lib/arm-linux-gnueabihf/pkgconfig"
    "${CMAKE_SYSROOT}/usr/share/pkgconfig"
    "${CMAKE_SYSROOT}/usr/local/share/pkgconfig"
)
    if(_dir AND EXISTS "${_dir}")
        list(APPEND _PKGCONFIG_DIRS "${_dir}")
    endif()
endforeach()

if(_PKGCONFIG_DIRS)
    list(JOIN _PKGCONFIG_DIRS ":" _PKGCONFIG_LIBDIR)
    set(ENV{PKG_CONFIG_LIBDIR} "${_PKGCONFIG_LIBDIR}")
endif()

message(STATUS "FPGA_BUILDROOT_ROOT   = ${FPGA_BUILDROOT_ROOT}")
message(STATUS "C compiler            = ${CMAKE_C_COMPILER}")
message(STATUS "C++ compiler          = ${CMAKE_CXX_COMPILER}")
if(CMAKE_SYSROOT)
    message(STATUS "Target sysroot        = ${CMAKE_SYSROOT}")
else()
    message(WARNING "Target sysroot not found. Falling back to toolchain default system paths.")
endif()
