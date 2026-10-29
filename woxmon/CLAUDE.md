# CLAUDE.md — woxmon project memory

Read this first. It records what woxmon is, the decisions already made (do not
re-litigate them without the owner), how the build works, and the traps found.
Keep it up to date when something important changes. User-facing details are
in README.md.

## 1. What woxmon is

- **woxmon** (long name **WiamOX Monitor**) is the terminal system monitor of
  the **WiamOX** Arch-based distribution: CPU, memory, disks, network, GPU
  (NVIDIA/AMD/Intel) and processes. Created and owned by **Wiam Khader**
  (Wiam@wiamox.com). Lives in the folder `woxmon/` of `wiamoxxx/wiamox-pkgs`
  (owner, 29.10.2026: a folder there, not its own repo or a submodule).
- C++23, CMake, no runtime dependencies besides glibc/libstdc++ (NVML and ROCm
  SMI are `dlopen`ed when present). Linux only.
- Packaged by `PKGBUILD` in this folder; built with `scripts/build.sh woxmon`
  (wiamox-pkgs root) into woxKitchen.

## 2. Decisions (owner, 29.10.2026)

| Topic | Decision |
|---|---|
| Base | A **fresh copy** (no upstream history, not a GitHub fork) of an existing Apache-2.0 terminal monitor, release 1.4.8 (commit `cf1da590`), by Aristocratos (jakob@qvantnet.com). Its UI and main functions are kept. |
| Upstream | **None.** No upstream remote, no merges: the app rarely needs updates and is ours from here on. |
| Old name | **Must not appear anywhere** (UI, help, `--version`, man page, config/log paths, docs, file names, identifiers, comments). `check()` in the PKGBUILD fails if it finds it in the tree, the binary or the man page. Write it nowhere, not even in this file. |
| License | Apache-2.0 stays. Kept as the license requires: `LICENSE` and the original author's copyright line at the top of the source files. Every changed file also carries `Copyright 2026 Wiam Khader (Wiam@wiamox.com): changed for woxmon (WiamOX Monitor)` (Apache-2.0 §4b). No credit in the UI or README (owner). New files: `// SPDX-License-Identifier: Apache-2.0` + Wiam's copyright. Bundled `include/fmt` and `source/linux/intel_gpu_top` stay MIT with their notices. |
| Trimmed | macOS and BSD code removed (`unifdef`), static-link and static-ROCm build options removed, the ~40 bundled third-party themes removed (built-in `Default` and `TTY` remain; theme folders still work), snap, upstream Makefile, CI, images. |
| GPU box | **On by default**: `shown_boxes = "cpu mem net proc gpu0"`. Without a GPU, or when the terminal is too small for it at start (80×24 is), the GPU box is hidden **for that run only** (`Boxes::start_with` in `source/woxmon.cpp`); on exit the config keeps what the user had, unless they changed the boxes themselves. |
| Names and IDs | Binary `woxmon`; desktop file + icon `com.wiamox.woxmon` (Terminal=true); config `~/.config/woxmon/woxmon.conf`; themes `~/.config/woxmon/themes`, `/usr/share/woxmon/themes`; log `~/.local/state/woxmon.log`; namespaces/identifiers `woxmon_*`, CMake options `WOXMON_GPU`, `WOXMON_LTO`. |
| Look | Same UI as the base. Banner "WOXMON" in the WiamOX gradient (`#22d3ee → #60a5fa → #a78bfa`), version right of its shadow row. Icon: WiamOX tile, load graph in the gradient, emerald dot (family of wed/woxed/woxbrowser/AI Center). |
| Version | **1.0.0**, only in `project(... VERSION)` in `CMakeLists.txt` → `config.h` (`WOXMON_VERSION`) → `Global::Version`; the PKGBUILD reads the same line. |
| Bug reports | Help page and man page say `Wiam@wiamox.com` (the repo is private). |
| setcap | Not done by the package. README explains `sudo setcap cap_perfmon,cap_dac_read_search=+ep /usr/bin/woxmon` for the Intel GPU and CPU watts. |

## 3. Build

- Builds run **as user `lol` inside the `wiamox-build` distrobox** (Arch),
  never as root.
- Dev build: `cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON && cmake --build build && ctest --test-dir build && ./build/woxmon`.
  Needs GCC ≥ 14 (C++23: `std::expected`, `std::ranges::to`).
- **Package:** prepare() takes this folder as **committed in HEAD** (`git archive`
  run in the folder only takes the folder;
  `WOX_UNCOMMITTED=1` adds uncommitted changes to tracked files). build() =
  CMake Release (LTO on), check() = GoogleTest suite (`gtest` from the system,
  no internet), `--version`, default `shown_boxes`, old-name scan. package()
  adds PNG icons (rsvg-convert), README, licenses, empty `/usr/share/woxmon/themes`.
  Build time: about a minute.

## 4. Status

- 29.10.2026: **1.0.0** created. Built and tested in Claude's environment
  (Ubuntu, GCC 14.2): no compiler warnings, 3/3 tests, PKGBUILD functions run
  by hand with a stand-in for makepkg; UI checked in tmux (main screen, menu,
  help, options; no GPU there, so the GPU box path "no GPU → hidden for this
  run, config keeps gpu0" was tested, the "terminal too small" path only
  by review). **Not yet built with makepkg on the build machine, not yet run
  with a real GPU.**

## 5. Traps

- **The code folder is `source/`, not `src/`.** With the PKGBUILD in the repo
  root, makepkg uses `./src` as its work folder when `BUILDDIR` is not set,
  and `--cleanbuild` deletes it.
- `unifdef` stops at C++14 digit separators (`1'000`) with "Unterminated char
  literal" and **truncates the file**; use `unifdef -t`.
- On a first start (no config file) the whole config is written on exit, so
  any value changed only for the run (the hidden GPU box) must be put back
  before `Config::write()` (done in `clean_quit`).
- Mixed compilers break LTO: the Intel GPU reader is C, so C and C++ compiler
  must be the same GCC version (`lto1: bytecode stream ... LTO version`).

## 6. Conventions

- Keep README.md (user-facing, English) and this file in sync; the wiamox-pkgs
  root CLAUDE.md/README.md list woxmon too.
- New source files: `woxmon_*.cpp/.hpp` in `source/`, SPDX header + Wiam's copyright.
- Bump `VERSION` in `CMakeLists.txt` (and `pkgrel` back to 1) for a release,
  add a CHANGELOG.md entry, and update the version badge in README.md.
- README.md is GitHub-style (logo, badges, screenshots in `docs/`). The
  screenshots are real woxmon screens: run it in tmux, `tmux capture-pane -e -p`,
  replay the capture in xterm.js (canvas renderer draws box/braille glyphs)
  and screenshot it with Playwright. Keep `docs/` small (4 screenshots + logo).
