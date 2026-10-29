# SPDX-License-Identifier: Apache-2.0

# GoogleTest from the system (Arch: gtest), so the build needs no internet
find_package(GTest REQUIRED)

add_library(libwoxmon_test)
target_include_directories(libwoxmon_test PUBLIC ${PROJECT_SOURCE_DIR}/source)
target_link_libraries(libwoxmon_test libwoxmon GTest::gtest_main)

add_executable(woxmon_test cpu_names.cpp tools.cpp)
target_link_libraries(woxmon_test libwoxmon_test)

include(GoogleTest)
gtest_discover_tests(woxmon_test)
