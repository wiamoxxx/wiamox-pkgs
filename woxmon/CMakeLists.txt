# SPDX-License-Identifier: Apache-2.0
#
# CMake configuration for woxmon (WiamOX Monitor). Linux only.
#

cmake_minimum_required(VERSION 3.25)

if("${CMAKE_CURRENT_SOURCE_DIR}" STREQUAL "${CMAKE_CURRENT_BINARY_DIR}")
  message(FATAL_ERROR "In-source builds are not allowed")
endif()

project("woxmon"
  VERSION 1.0.0
  DESCRIPTION "WiamOX Monitor - system monitor of WiamOX"
  HOMEPAGE_URL "https://github.com/wiamoxxx/wiamox-pkgs"
  LANGUAGES CXX
)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
  message(FATAL_ERROR "woxmon is built for Linux (WiamOX) only, not ${CMAKE_SYSTEM_NAME}")
endif()

include(CheckIPOSupported)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_COLOR_DIAGNOSTICS ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(WOXMON_GPU "Enable GPU support (NVIDIA, AMD, Intel)" ON)

# Enable LTO in release builds by default
if(CMAKE_BUILD_TYPE MATCHES "Rel(ease|WithDebInfo)")
  option(WOXMON_LTO "Enable LTO" ON)
else()
  option(WOXMON_LTO "Enable LTO" OFF)
endif()

add_executable(woxmon source/main.cpp)
add_library(libwoxmon OBJECT
  source/woxmon.cpp
  source/woxmon_cli.cpp
  source/woxmon_config.cpp
  source/woxmon_draw.cpp
  source/woxmon_input.cpp
  source/woxmon_log.cpp
  source/woxmon_menu.cpp
  source/woxmon_shared.cpp
  source/woxmon_theme.cpp
  source/woxmon_tools.cpp
  source/linux/woxmon_collect.cpp
)

target_link_libraries(woxmon libwoxmon)

if(WOXMON_LTO)
  check_ipo_supported()
  set_target_properties(woxmon PROPERTIES INTERPROCEDURAL_OPTIMIZATION ON)
  set_target_properties(libwoxmon PROPERTIES INTERPROCEDURAL_OPTIMIZATION ON)
endif()

if(WOXMON_GPU)
  add_subdirectory(source/linux/intel_gpu_top)
endif()

# Generate build info
execute_process(
  COMMAND "git" "rev-parse" "--short" "HEAD"
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  OUTPUT_VARIABLE GIT_COMMIT
  OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
set(CONFIGURE_COMMAND
    "cmake -DWOXMON_GPU=${WOXMON_GPU}"
)
get_filename_component(CXX_COMPILER_BASENAME "${CMAKE_CXX_COMPILER}" NAME)
set(COMPILER "${CXX_COMPILER_BASENAME}")
set(COMPILER_VERSION "${CMAKE_CXX_COMPILER_VERSION}")
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/source/config.h.in ${CMAKE_CURRENT_BINARY_DIR}/config.h @ONLY IMMEDIATE)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

include(CheckCXXSourceCompiles)
include(CheckCXXSymbolExists)

check_cxx_source_compiles(
  "
  #include <version>
  #if __cpp_lib_optional < 202110L
  #error \"Missing __cpp_lib_optional < 202110L\"
  #endif
  int main() { return 0; }
  "
  HAS_CXX_OPTIONAL_MONADS
)
if(NOT HAS_CXX_OPTIONAL_MONADS)
  message(FATAL_ERROR "The compiler doesn't support std::optional::and_then")
endif()
check_cxx_symbol_exists("__cpp_lib_expected" "version" HAS_CXX_EXPECTED)
if(NOT HAS_CXX_EXPECTED)
  message(FATAL_ERROR "The compiler doesn't support std::expected")
endif()
check_cxx_symbol_exists("__cpp_lib_ranges" "version" HAS_CXX_RANGES)
if(NOT HAS_CXX_RANGES)
  message(FATAL_ERROR "The compiler doesn't support std::ranges")
endif()
check_cxx_symbol_exists("__cpp_lib_ranges_to_container" "version" HAS_CXX_RANGES_TO_CONTAINER)
if(NOT HAS_CXX_RANGES_TO_CONTAINER)
  message(FATAL_ERROR "The compiler doesn't support std::ranges::to")
endif()
check_cxx_symbol_exists("__cpp_lib_string_contains" "version" HAS_CXX_STRING_CONTAINS)
if(NOT HAS_CXX_STRING_CONTAINS)
  message(FATAL_ERROR "The compiler doesn't support std::string::contains")
endif()

target_compile_options(libwoxmon PUBLIC -Wall -Wextra -Wpedantic -fstack-clash-protection)

include(CheckCXXCompilerFlag)

check_cxx_compiler_flag(-fstack-protector HAS_FSTACK_PROTECTOR)
if(HAS_FSTACK_PROTECTOR)
  target_compile_options(libwoxmon PUBLIC -fstack-protector)
endif()
check_cxx_compiler_flag(-fcf-protection HAS_FCF_PROTECTION)
if(HAS_FCF_PROTECTION)
  target_compile_options(libwoxmon PUBLIC -fcf-protection)
endif()

target_compile_definitions(libwoxmon PUBLIC
  FMT_HEADER_ONLY
  _FILE_OFFSET_BITS=64
  $<$<CONFIG:Debug>:_GLIBCXX_ASSERTIONS _LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_DEBUG>
)

target_include_directories(libwoxmon SYSTEM PUBLIC include)

# Enable pthreads
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
target_link_libraries(libwoxmon Threads::Threads)

# GPU support: NVML (NVIDIA) and ROCm SMI (AMD) are loaded at runtime with dlopen,
# so neither is needed to build; Intel comes from intel_gpu_top above.
if(WOXMON_GPU)
  target_compile_definitions(libwoxmon PUBLIC GPU_SUPPORT)

  target_link_libraries(libwoxmon ${CMAKE_DL_LIBS})
endif()

# Man page from manpage.md (needs lowdown)
find_program(LOWDOWN_EXECUTABLE lowdown)

if(LOWDOWN_EXECUTABLE)
  add_custom_command(
    OUTPUT woxmon.1
    COMMAND lowdown -s -T man -o woxmon.1 ${CMAKE_CURRENT_SOURCE_DIR}/manpage.md
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/manpage.md
    VERBATIM
  )
  add_custom_target(generate_manpage ALL DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/woxmon.1)
  install(FILES "${CMAKE_CURRENT_BINARY_DIR}/woxmon.1" DESTINATION "share/man/man1")
else()
  message(STATUS "Command 'lowdown' not found: skipping generating man page woxmon.1")
endif()

install(TARGETS woxmon RUNTIME)
install(FILES "packaging/com.wiamox.woxmon.desktop" DESTINATION "share/applications")
install(FILES "packaging/com.wiamox.woxmon.svg" DESTINATION "share/icons/hicolor/scalable/apps")

include(CTest)
if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
