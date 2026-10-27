# CLAUDE.md — wiamox-pkgs project memory

Read this first. It records what this repo is, the decisions already made
(do not re-litigate them without the owner), how the build works, and the
traps that were found the hard way. Keep it up to date when you change
something important. User-facing details are in README.md.

## 1. What wiamox-pkgs is

- The **build workshop for WiamOX's own packages** (WiamOX = Arch-based
  distro by **Wiam Khader**, Wiam@wiamox.com). It turns sources into
  `.pkg.tar.zst` files and adds them to **woxKitchen**, the local pacman
  repo on the build machine (`/home/lol/woxKitchen`, database name
  `custom`, listed as `[custom]` **before `[core]`** in woxclean1's
  `pacman.conf`).
- It is never read by the ISO build. mkarchiso and woxclean1's
  `build-wiamox-repo.sh` only read woxKitchen, however packages got there.
- `scripts/publish.sh` can publish woxKitchen as the online repo
  `[woxkitchen]` (GitHub release `x86_64`). Not used yet: the repo is
  private and pacman cannot download private release files.

## 2. Packages

| Package | Folder | Source | Notes |
|---|---|---|---|
| `linux`, `linux-headers` | `linux/` | kernel tree on disk (`WIAMOX_KERNEL_SRC`) | named `linux` to replace Arch's; config from fragments; ~30 GB to build |
| `calamares-wiamox` | `calamares-wiamox/` | git submodule (wiamoxxx/calamares-wiamox) | config-only, `--nodeps` |
| `woxed` | `woxed/` | git submodule (wiamoxxx/woxed) | needs internet at build time; `WOXED_JOBS` for parser compile |
| `ai-center` | `ai-center/` | git submodule (wiamoxxx/ai-center) | PKGBUILD lives in that repo; launcher only (ComfyUI container and image bundles were removed in 0.7.0), `arch=any`, `--nodeps` (no makedepends); project memory in its CLAUDE.md |
| `wiamox-opencode` | `wiamox-opencode/` | npm tarball `opencode-linux-x64` (upstream prebuilt Bun binary), sha256-pinned | `provides=(opencode)`; `!strip` (strip corrupts the binary); wrapper sets offline env; `ai-center` depends on it; no makedepends → `--nodeps`; packs x64 + x64-baseline, wrapper picks by avx2; LSPs = optdepends only |
| `wiamox-llama.cpp-cuda` | `wiamox-llama.cpp-cuda/` | git source `ggml-org/llama.cpp`, pinned by tag `bNNNN` + commit | `provides/conflicts=(llama.cpp)`; one package per GPU variant (ROCm later = `wiamox-llama.cpp-rocm/`); `/usr/bin/llama-server` (+cli, bench, quantize, gguf-split, perplexity, mtmd-cli for vision), libs in `/usr/lib/wiamox-llama.cpp` via RPATH; `GGML_NATIVE=OFF`, no curl; `ai-center` depends on `llama.cpp`; has makedepends → `--syncdeps` (cuda, cmake) |
| `wiamox-comfyui-cuda` | `wiamox-comfyui-cuda/` | ComfyUI git tag `v$pkgver` + PyPI + PyTorch wheel index + `nodes.txt` (git, pinned by commit); all fetched at build time | `provides/conflicts=(comfyui)`; self-contained: uv-managed Python 3.12 in `/usr/lib/wiamox-comfyui/python`, torch `cu130` wheels (CUDA inside, only `nvidia-utils` from the system), `/usr/bin/wiamox-comfyui` wrapper (offline env), nodes copied to the user's folder by AI Center; `!strip`; `check()` = CPU smoke test; makedepends `uv git` → `--syncdeps`; ROCm later = `_backend=rocm7.2` copy; `ai-center` optdepends it |
| `calamares` | `aur/calamares/` (gitignored) | the AUR, cloned/updated by build.sh | links libpython → rebuild after every Python update (`--force`) |
| `coreutils` | `coreutils/` | coreutils tree on disk (`WIAMOX_COREUTILS_SRC`) | release tarball or git clone + gnulib; Arch's configure flags |

## 3. Decisions (agreed with the owner)

| Topic | Decision |
|---|---|
| Own code changes | Built **from a source tree on disk** that Wiam edits directly (kernel, coreutils). **Not** as patch files on top of Arch's recipe — that approach was built (PR #4) and replaced at Wiam's request (PR #5). |
| Tree on disk | Never modified by a build: copied into `build/` without `.git` / object files, then cleaned (`mrproper` / `distclean`). |
| Versions | pkgver read from the source tree; rebuilding the same version needs a `pkgrel` bump. build.sh refuses to overwrite a version woxKitchen has (`--force` overrides). |
| AUR packages | Recipe cloned into `aur/<name>`, every new recipe / change shown and confirmed before building (AUR = third-party). |
| woxKitchen database | Exactly **one** database, **`custom.db.tar.zst`**. Add by hand only with `repo-add -R …/custom.db.tar.zst <file>`. |
| Build environment | Nothing from `$HOME` in a build (PATH entries, venv/conda/PYTHONPATH/LD_LIBRARY_PATH cleared, `PYTHONNOUSERSITE=1`). |
| Library check | Before `repo-add`, every ELF in the package must resolve all libs on this machine and none from `/home`; otherwise nothing goes to woxKitchen (`--no-libcheck` to skip). |
| Dependencies | `makepkg --syncdeps` without `--rmdeps`: the library check needs the runtime deps installed. |

## 4. scripts/

- `common.sh` (sourced): `load_conf` (local.conf, env `WIAMOX_*` wins),
  `kitchen_db` (follows the `custom.db` link — what pacman reads — and
  **dies if there are two databases**), `clean_build_env`, `confirm`,
  `recipe_update` (clone/update a recipe repo, show diff without
  `.SRCINFO`, optional confirmation), `check_libs` (ldd over every ELF in
  the built packages; libraries shipped in the package count as present).
- `build.sh <pkg> [--install] [--no-kitchen] [--force] [--no-libcheck] [--skip-existing]`
  (`--skip-existing`: version already in woxKitchen → message, exit 0; used by
  wiamox-forge's `wiamox-build all`, 27.10.2026):
  fetch submodule / AUR recipe → load conf → clean env → per-package
  pre-checks (kernel: version + 30 GB; coreutils: tree + version) → version
  exists in woxKitchen? → `makepkg --cleanbuild --syncdeps --force --log`
  → library check → copy to woxKitchen + `repo-add -R` → optional install.
  `PKGDEST=out/`, `LOGDEST=build/logs/`, `SRCDEST=build/sources/`
  (keeps submodules clean).
- `publish.sh [--dry-run]`: upload current woxKitchen packages + a fresh
  `woxkitchen` database to the GitHub release, verify downloads.

## 5. Lessons learned (traps)

- **libpython trap (calamares):** a `~/.local/bin/python3.12` (from `uv`)
  came first in PATH; CMake linked calamares against it. The package then
  failed on the ISO and on the build machine with
  `libpython3.12.so.1.0: cannot open shared object file`. Rebuilding with
  plain makepkg kept reproducing it. → clean env + library check. The build
  log must say `Found Python3: /usr/bin/python3...`.
- **Python upgrades break calamares**: it must be rebuilt (`--force`, same
  version) after every Arch Python / boost / yaml-cpp / kpmcore bump. The
  ISO uses Arch's `*-testing` repos, so match the build machine to them.
- **Two woxKitchen databases**: a manual `repo-add` into
  `custom.db.tar.gz` next to build.sh's `custom.db.tar.zst` re-pointed
  `custom.db`; pacman lost the kernel in `[custom]` and the ISO + offline
  repo got Arch's `linux` 7.2 instead of the WiamOX 7.0.12. Also: a
  package listed in two DBs can carry different checksums. Fix = delete
  both, `repo-add custom.db.tar.zst *.pkg.tar.zst`.
- **Arch's coreutils recipe** builds from a git checkout in
  `$srcdir/coreutils` and its `prepare()` applies every `*.patch` in
  `source=()` itself (relevant if a patch approach is ever revisited).
- **coreutils release tarball**: `make install` already creates the
  `LC_TIME/coreutils.mo` links (Arch adds them only because it builds from
  git); the PKGBUILD skips existing ones. `./configure` refuses to run as
  root (makepkg never runs as root; in tests use `FORCE_UNSAFE_CONFIGURE=1`).
- **`cmd | grep -q` under `set -o pipefail`** fails whenever grep quits before
  cmd is done writing (SIGPIPE). build.sh's makedepends test did that and
  silently built calamares with `--nodeps` (`cmake: command not found`,
  26.10.2026). Read the output into a variable first, then grep it.
- `ldd` exits non-zero exactly when a library is missing — never use its
  exit status to skip files in checks; only its output counts.
- The private GitHub repos (incl. the submodules) need a login on the
  build machine: `gh auth login` + `gh auth setup-git`, **or** (current build
  machine) `git config --global url."git@github.com:wiamoxxx/".insteadOf "https://github.com/wiamoxxx/"`
  with the SSH key.
- **/tmp is a RAM disk** (tmpfs, half the RAM = 7.7 GB here): uv's wheel
  unpacking (comfyui-impact-pack failed) and check_libs ran out of space with
  ComfyUI. build.sh now sets `TMPDIR=$BUILDDIR/tmp`; check_libs ignores
  libraries that resolve inside its own unpack folder (under /home now).
- `--syncdeps` asks pacman "Proceed with installation?"; without a terminal
  (e.g. Claude running build.sh) that fails with "Could not resolve all
  dependencies". Pre-install the deps with `pacman -S --needed --noconfirm --asdeps …` first.

## 6. Status (keep updated)

- 04.10.2026: `ai-center` 0.3.0 (submodule pinned to `9513a89`, merged `main` of wiamoxxx/ai-center: ComfyUI image fixes (node submodules, pyproject deps, import disk-space check, `--extra-arg`) on top of the 0.3.0 look with themes, logo, status borders; 0.2.0 added ComfyUI as a Podman container, `containers/` + optional image bundles in the package). `build.sh` passes `WIAMOX_AI_CENTER_IMAGES` to the PKGBUILD as `AI_CENTER_IMAGES`; `check_libs` skips the bundles. `makepkg` not run yet; no bundle built yet. Submodule pinned to ai-center 0.5.1 (`29abf9e`, 19.10.2026); now ai-center 0.7.0 (`65a4da8`, branch claude/focused-feynman-if7g75 of wiamoxxx/ai-center, 22.10.2026).
- Done (PRs #1–#5, 30.09.–01.10.2026): woxed + calamares + coreutils in
  build.sh, clean env, library check, one-database guard, coreutils from a
  source tree.
- **Tested here only partly** (Claude's environment is not Arch and cannot
  reach the AUR, gitlab.archlinux.org or GNU): flow tests with stand-in
  makepkg/repo-add; a real prepare/build/package of the coreutils 9.10
  tarball. **Not yet run on the build machine:** `build.sh woxed`,
  `build.sh calamares` (first AUR clone), `build.sh coreutils`, a git clone
  as coreutils source, `make check`.
- The kernel currently in woxKitchen is `linux 7.0.12.arch1-1`, apparently
  built from Arch's kernel recipe, not from `linux/` here (that would be
  `7.x.y-1`, `uname -r` ending in `-wiamox`).
- woxKitchen is not reachable from installed systems → no updates for own
  packages after install until `publish.sh` is used (needs a public repo).

- 08.10.2026: added `wiamox-opencode` 1.18.35 (recipe lives here, not in ai-center). `ai-center` 0.4.0 depends on `opencode`, so build it first and list it in woxclean1 `packages.x86_64`. `makepkg` not run yet; the binary itself was run offline against a fake OpenAI server in Claude's environment.

- 19.10.2026: added `wiamox-llama.cpp-cuda` b11722 (AI Center no longer uses a llama.cpp container; `ai-center` 0.5.1 depends on `llama.cpp`). Built and tested on the build machine (shipped in woxKitchen). List it in woxclean1 `packages.x86_64`; `ai-center` submodule needs `git submodule update --remote ai-center` (0.5.x).

- 19.10.2026: added `wiamox-yue2.cpp-cuda` 20261016 (YuE2 song generation, backs the AI Music card). Pinned by commit (`yue2.cpp` + `ggml` commit, ggml submodule initialised in prepare() from the local clone and hash-checked). `provides/conflicts=(yue2.cpp)`, binaries `yue-server yue-synth yue-plan` in `/usr/lib/wiamox-yue2.cpp` (RUNPATH), CUDA archs `75-virtual;80-virtual;86-real;89-real;120a-real`. Built into woxKitchen. Listed in the Calamares "AI" bundle (`calamares-wiamox` netinstall.conf), not in the ISO live packages. `ai-center` 0.6.x optdepends on it. GGUFs are not packaged (user provides them in `~/aihub/models/yue2`); first real run done 19.10.2026: AI Music card works, **production ready**, no more work needed for now.

- 19.10.2026: added `wiamox-wox` 0.1.0 (local sources in `wiamox-wox/`: `wox` Python stdlib, `hook.zsh`, `hook.bash`). `wox why` (alias `why`, `wox diagnose`) asks llama-server (127.0.0.1:8080, `WOX_LLAMA_URL`) to explain the last failed command. The hooks are sourced from the skel `.zshrc`/`.bashrc` (woxclean1) **before starship** and keep failed commands only (no output) in `$XDG_RUNTIME_DIR/wox/<shellpid>.log`: max 8 entries, max 1 h, removed at shell exit, dead shells swept at start. Output is obtained by re-running the command (asks first), paste, tmux screen, or `cmd 2>&1 | wox why`; capturing stderr live was rejected (breaks isatty/colours). Tested with a fake llama-server through a pty in zsh and bash. Version 1 = one answer, no chat; `--screen` (vision) planned.

- 27.10.2026: `wiamox-wox` 0.2.0: package commands, thin pacman wrappers that print the real command first and pass extra flags through: `wox install|i` = `sudo pacman -Sy` (**`-Sy`, not `-S`/`-Syu`: Wiam's decision**; users run `wox update` first), `remove|rm` = `-Rns`, `update|up` = `-Syu`, `search|s` = `-Ss`, `info` (`-Qi` if installed, else `-Si`), `list` = `-Qe`, `clean` = `-Rns` of `pacman -Qdtq`. No sudo when already root. zsh (`_wox`) + bash (`wox.bash`) completion with package names. The hooks now skip only `wox why`/`wox diagnose`/`why`, so a failed `wox install` can be explained. `check()` runs `test_wox.py` (fake sudo/pacman on PATH). Merged to main; not yet rebuilt into woxKitchen.

## 7. Related repos

- `wiamoxxx/woxclean1` — the archiso profile (ISO). `pacman.conf` with
  `[custom]` first; `build-wiamox-repo.sh` builds the offline `[wiamox]`
  repo and also stops on two databases. Project memory:
  `docs/wiamox-distro.md` (German).
- `wiamoxxx/calamares-wiamox` — installer config (submodule here).
- `wiamoxxx/woxed` — WiamOX Editor (submodule here), own `CLAUDE.md`.
- `wiamoxxx/WiamOX-Interface` — Quickshell desktop shell (submodule of
  woxclean1, not built here).

## 8. Conventions

- Run build.sh as the normal user, never as root.
- `local.conf` is per machine and not committed; `local.conf.example`
  documents every setting.
- Commit PKGBUILD version changes that makepkg writes (`pkgver`/`pkgrel`).
- Keep README.md (user-facing, English) and this file in sync.

- 22.10.2026: added `wiamox-comfyui-cuda` 0.38.2 (ComfyUI is now native, no Podman; `ai-center` 0.7.0 dropped the container, the image bundles and `WIAMOX_AI_CENTER_IMAGES`). Written and the mechanics tested in Claude's environment against a stand-in ComfyUI (uv standalone Python relocated into the package dir, `check()` smoke test, wrapper, AI Center start flow, node sync); **not built with the real ComfyUI/PyTorch** (no GitHub/PyTorch index access there): first real build on the build machine is the test. Not yet in the Calamares "AI" bundle (`calamares-wiamox` netinstall.conf).

- **26.10.2026 — new build machine** (CachyOS host, old one formatted, woxKitchen
  rebuilt from empty). Packages are built in the **Arch build box** (distrobox
  `wiamox-build`, Arch + testing + multilib, shared home; setup in
  `/home/lol/Projects/BUILD-MACHINE.md`), so they link against the same libraries
  as the ISO and not CachyOS's `-march=native`/v3 builds. In woxKitchen now:
  `calamares-wiamox` 1.7.5-1, `calamares` 3.4.2-2 (+ `-debug`; Found Python3
  /usr/bin/python3.14, 3.14.9), `woxed` 1.0.0-1 (submodule `0bbd0c3`, check()
  incl. `unshare -rn` passes in the box). Still to rebuild: wiamox-opencode,
  wiamox-llama.cpp-cuda, wiamox-yue2.cpp-cuda, wiamox-comfyui-cuda, ai-center,
  wiamox-wox, coreutils + linux (their source trees on disk were lost with the format).
  Later the same day also built: wiamox-opencode 1.18.35-2, wiamox-wox 0.1.0-1,
  ai-center 0.7.0-1, wiamox-llama.cpp-cuda 11722-1, wiamox-yue2.cpp-cuda
  20261016-1 and the **first real wiamox-comfyui-cuda 0.38.2-1** (4.4 GB; all 12
  nodes install, CPU smoke test passed; not yet run on the GPU). Portability
  checked with objdump: calamares, woxed parsers, llama.cpp and yue2 contain no
  AVX/AVX-512 at all (ggml `GGML_AVX*/FMA/F16C = OFF`, SSE2 baseline; the
  "runtime CPU feature dispatch" comment in the llama.cpp PKGBUILD is not what
  this config does: that needs `GGML_BACKEND_DL=ON` + `GGML_CPU_ALL_VARIANTS=ON`).
  Still missing: coreutils + linux.
- ComfyUI library check: only optional plugins miss libraries (ROCm hip backend,
  onnxruntime TensorRT, nvshmem MPI/IB/UCX transports, cufile RDMA, numba TBB,
  Python `_crypt`/libcrypt.so.1); added with `repo-add -R` by hand after
  reviewing that list (= `--no-libcheck`). Re-check the list on version bumps.
