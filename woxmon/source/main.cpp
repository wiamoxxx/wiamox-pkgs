// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Wiam Khader (Wiam@wiamox.com): changed for woxmon (WiamOX Monitor)

#include "woxmon.hpp"

#include <iterator>
#include <ranges>
#include <string_view>
#include <vector>

auto main(int argc, const char* argv[]) -> int {
	return woxmon_main(std::views::counted(std::next(argv), argc - 1) | std::ranges::to<std::vector<std::string_view>>());
}
