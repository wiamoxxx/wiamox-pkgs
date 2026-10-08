# CLAUDE.md — wiamox-pkgs project memory

Read this first. It records what this repo is, the decisions already made
(do not re-litigate them without the owner), how the build works, and the
traps that were found the hard way. Keep it up to date when you change
something important. User-facing details are in README.md.

## 1. What wiamox-pkgs is

- The **build workshop for WiamOX's own packages** (WiamOX = Arch-based
  distro by **Wiam Khader**, admin@wiamox.com). It turns sources into
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
| `ai-center` | `ai-center/` | git submodule (wiamoxxx/ai-center) | PKGBUILD lives in that repo; launcher + ComfyUI build files, optional image bundles from `WIAMOX_AI_CENTER_IMAGES` (GBs), `arch=any`, `--nodeps` (no makedepends); project memory in its CLAUDE.md |
| `wiamox-opencode` | `wiamox-opencode/` | npm tarball `opencode-linux-x64` (upstream prebuilt Bun binary), sha256-pinned | `provides=(opencode)`; `!strip` (strip corrupts the binary); wrapper sets offline env; `ai-center` depends on it; no makedepends → `--nodeps`; AVX2 CPU |
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
- `build.sh <pkg> [--install] [--no-kitchen] [--force] [--no-libcheck]`:
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
- `ldd` exits non-zero exactly when a library is missing — never use its
  exit status to skip files in checks; only its output counts.
- The private GitHub repos (incl. the submodules) need a login on the
  build machine: `gh auth login` + `gh auth setup-git`.

## 6. Status (keep updated)

- 04.10.2026: `ai-center` 0.3.0 (submodule pinned to `9513a89`, merged `main` of wiamoxxx/ai-center: ComfyUI image fixes (node submodules, pyproject deps, import disk-space check, `--extra-arg`) on top of the 0.3.0 look with themes, logo, status borders; 0.2.0 added ComfyUI as a Podman container, `containers/` + optional image bundles in the package). `build.sh` passes `WIAMOX_AI_CENTER_IMAGES` to the PKGBUILD as `AI_CENTER_IMAGES`; `check_libs` skips the bundles. `makepkg` not run yet; no bundle built yet. Newer: `git submodule update --remote ai-center`.
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
