# wiamox-pkgs

The WiamOX packages that don't come from Arch, as build recipes (PKGBUILDs),
the script that builds them into your local woxKitchen repo, and the
script that publishes woxKitchen online as the pacman repo `[woxkitchen]`.

| Folder | Package | Source |
|---|---|---|
| `linux/` | `linux`, `linux-headers`: the WiamOX kernel | a kernel source tree **on your disk** (with your own edits) |
| `calamares-wiamox/` | `calamares-wiamox`: installer branding and config | git submodule → [wiamoxxx/calamares-wiamox](https://github.com/wiamoxxx/calamares-wiamox) |
| `ai-center/` | `ai-center`: WiamOX AI Center (local AI launcher for llama.cpp, ComfyUI, AI Music, OpenCode) | git submodule → [wiamoxxx/ai-center](https://github.com/wiamoxxx/ai-center) |
| `wiamox-opencode/` | `wiamox-opencode` (provides `opencode`): the OpenCode coding agent, offline build | the upstream prebuilt binary from the npm registry, pinned by sha256, downloaded at build time |
| `wiamox-llama.cpp-cuda/` | `wiamox-llama.cpp-cuda` (provides `llama.cpp`): `llama-server` for AI Center, CUDA build | llama.cpp from GitHub, pinned by commit, built at build time |
| `wiamox-comfyui-cuda/` | `wiamox-comfyui-cuda` (provides `comfyui`): ComfyUI for AI Center, own Python + PyTorch, works offline, CUDA build | ComfyUI release tag, PyPI and the PyTorch wheel index, custom nodes pinned by commit; all fetched at build time |
| `woxed/` | `woxed`: the WiamOX Editor | git submodule → [wiamoxxx/woxed](https://github.com/wiamoxxx/woxed) |
| `wed/` | `wed`: Wiam's Editor (GUI) | git submodule → [wiamoxxx/wed](https://github.com/wiamoxxx/wed) |
| `aur/calamares/` | `calamares`: the installer program | the AUR, cloned on first build (not part of this repo) |
| `coreutils/` | `coreutils`: the basic commands (`ls`, `cp`, ...) | a coreutils source tree **on your disk** (with your own edits) |

Finished packages go to `out/`, build logs to `build/logs/`, downloaded
sources to `build/sources/`.

Every build with `scripts/build.sh`:

- **runs without your home folder:** `~/...` entries are removed from
  `PATH`, and virtualenv/conda/`PYTHONPATH`/`LD_LIBRARY_PATH` settings
  are cleared. This way a Python from `uv` or pyenv can't end up linked
  into a package.
- **checks the libraries before `repo-add`:** every program and library
  in the new package must find the shared libraries it needs on this
  machine, and none may come from `/home`. If one doesn't, nothing goes
  into woxKitchen (`--no-libcheck` skips this check).
- **stops if woxKitchen has two databases** (e.g. `custom.db.tar.zst` and
  `custom.db.tar.gz`). pacman only reads the one `custom.db` points to and
  silently ignores packages that are only in the other. That once gave
  the ISO Arch's kernel instead of the one in woxKitchen. The error
  message shows how to build one database again. Add packages by hand
  only with `repo-add -R <woxKitchen>/custom.db.tar.zst <file>`.
- **installs what the package needs to build and run** (`makepkg --syncdeps`).
  It stays installed, because the library check needs it. `pacman -Qdt`
  lists what is no longer needed by anything, to remove it later.

## Setup (once per machine)

```sh
git clone --recurse-submodules https://github.com/wiamoxxx/wiamox-pkgs.git
cd wiamox-pkgs
cp local.conf.example local.conf
$EDITOR local.conf        # WIAMOX_KITCHEN, WIAMOX_KERNEL_SRC, WIAMOX_COREUTILS_SRC, ...
```

- The WiamOX repositories are private: log in once with
  `gh auth login` and `gh auth setup-git` (package `github-cli`),
  otherwise cloning the submodules fails with "Password authentication
  is not supported".
- Build machine: Arch-based, with `base-devel` installed. What each
  package needs to build is installed by makepkg when missing. On a
  non-Arch host (CachyOS, EndeavourOS, …) build in the WiamOX build box
  instead: [wiamox-forge](https://github.com/wiamoxxx/wiamox-forge)
  (`wiamox-forge load <box file>`, then `wiamox-build <pkg>` or
  `wiamox-build all`; `all` passes `--skip-existing`, so versions
  woxKitchen already has are skipped instead of stopping the run).
- Space: about **30 GB** free where it compiles (`build/` here, or
  `WIAMOX_BUILDDIR`) for the kernel, because its config has full debug
  info (needed for BTF). The other packages need far less.
- woxKitchen must exist and have at most one database (see above).

## Building the kernel

```sh
scripts/build.sh linux              # build, then add to woxKitchen
scripts/build.sh linux --install    # ... and install it on this machine
scripts/build.sh linux --no-kitchen # only build
```

What happens:

1. `pkgver` is read from your source tree's `Makefile` (7.2.8, 7.3.0.rc1, ...).
2. Your source tree is copied into the build folder, without `.git` and
   build leftovers, then cleaned with `make mrproper`. **Your own tree is
   never changed**, so you can keep editing and test-compiling in it.
3. The config is made the same way as `linux/config` was:
   `x86_64_defconfig`, then `wiamox-base.config` and
   `wiamox-drivers.config` merged on top, then `olddefconfig`.
   The build log then shows:
   - fragment lines the kernel did not accept (a dependency is missing,
     or the option no longer exists in this kernel version), and
   - how the result differs from `linux/config`.
   Both should be empty for 7.2.8. With a newer kernel, read them.
4. The kernel is compiled and split into `linux` and `linux-headers`.
   `uname -r` shows `7.2.8-wiamox`.
5. Both packages are added to woxKitchen with `repo-add`, replacing the
   previous version. The next woxclean1 ISO build uses them.

Your own kernel edits are kept as patches in `linux/patches/`; for a new
kernel version see [Your own edits as patches](#your-own-edits-as-patches-kernel-coreutils).

### Rebuilding the same kernel version

pacman only updates a package when its version goes up. After changing
the source or the config **without** a new kernel version, raise
`pkgrel` in `linux/PKGBUILD` (1 → 2). `build.sh` refuses to overwrite a
version woxKitchen already has, so you don't forget (`--force` to
override). A new kernel version resets `pkgrel` to 1 automatically.

`makepkg` writes the new `pkgver`/`pkgrel` into `linux/PKGBUILD`; commit
that, so the repo shows which version was built.

### Changing the config

- **Normal way:** edit `wiamox-base.config` / `wiamox-drivers.config`.
  After a successful build, refresh the reference with the config the
  package was built from:
  `cp build/linux/src/linux-wiamox/.config linux/config`
- **Using a complete config instead:** put it in `linux/config` and set
  `WIAMOX_KERNEL_CONFIG=full` in `local.conf`.

## Building calamares-wiamox

```sh
scripts/build.sh calamares-wiamox   # build, then add to woxKitchen
```

The folder is a git submodule: wiamox-pkgs records which commit of
calamares-wiamox it builds. After `git clone`, `build.sh` fetches it on
first use (or run `git clone --recurse-submodules`).

It is a config-only package, so it builds in seconds and nothing is
installed on the build machine for it (no `calamares`, `grub`, ...).

**Building a newer calamares-wiamox:**

1. Change calamares-wiamox in its own repo as usual and bump `pkgver`
   in its `PKGBUILD` (pacman only updates on a higher version).
2. Here, move the submodule to the latest `main` and record that:
   ```sh
   git submodule update --remote calamares-wiamox
   git commit -am "Bump calamares-wiamox to <version>"
   ```
3. `scripts/build.sh calamares-wiamox`

To try a change before pushing it, edit the files directly in
`calamares-wiamox/` here and build; `build.sh` warns that it is building
uncommitted changes. Commit and push them from inside that folder
afterwards (it is a normal clone of the calamares-wiamox repo).

## Building ai-center

```bash
scripts/build.sh ai-center
```

Builds the pinned version recorded in the `ai-center/` submodule: the
launcher only (arch `any`, needs `python-textual` and `python-tomlkit` from
Arch). The backends come from their own packages (`wiamox-llama.cpp-cuda`,
`wiamox-comfyui-cuda`, `wiamox-yue2.cpp-cuda`, `wiamox-opencode`); models
are per-user data. Run it with `wiamox-ai-center`.

To put it on the ISO, `ai-center` must be listed in woxclean1's
`packages.x86_64`. Newer version: change it in its own repo, bump
`pkgver`/`pkgrel`, then `git submodule update --remote ai-center`, commit,
build.

## Building wiamox-opencode

```bash
scripts/build.sh wiamox-opencode
```

Repackages OpenCode's own prebuilt binary (npm package
`opencode-linux-x64`, checked against a sha256 in the PKGBUILD). Needs
internet **at build time only**; the installed package never does: a wrapper
(`/usr/bin/opencode`) turns off update checks, the model-catalogue fetch,
LSP downloads and default plugins, and `git` + `ripgrep` come from Arch.
`ai-center` depends on `opencode`, so this must be in woxKitchen and listed
in woxclean1's `packages.x86_64` before `ai-center` can be installed.
Packs both the normal x64 binary and the `-baseline` one (CPUs without AVX2);
the wrapper picks by `avx2` in `/proc/cpuinfo`. Language servers (pyright,
typescript-language-server, gopls, rust-analyzer) are optdepends: OpenCode
never downloads them and works without them (no diagnostics after edits).
New version: change `pkgver`, run `updpkgsums` in `wiamox-opencode/`, build.

## Building wiamox-llama.cpp-cuda

```bash
scripts/build.sh wiamox-llama.cpp-cuda
```

Builds llama.cpp (tag pinned by commit in the PKGBUILD) with CUDA and
installs `/usr/bin/llama-server` (plus `llama-cli`, `llama-bench`,
`llama-quantize`); its libraries go to `/usr/lib/wiamox-llama.cpp`. One
package per GPU backend, all `provides=(llama.cpp)` / `conflicts=(llama.cpp)`;
`ai-center` depends on `llama.cpp` and just runs `llama-server` from `$PATH`.
ROCm later = a second folder `wiamox-llama.cpp-rocm/`. Needs `cuda` and
`cmake` (installed by `--syncdeps`), internet at build time only. CPU code is
a portable baseline (no `-march=native`); CUDA architectures are set in
`_cuda_archs`. New version: change `_tag`/`_commit`, `pkgrel=1`.
Must be in woxKitchen and in woxclean1's `packages.x86_64` before `ai-center`
can be installed.

## Building wiamox-comfyui-cuda

```bash
scripts/build.sh wiamox-comfyui-cuda
```

Builds ComfyUI as a **self-contained** package, so the installed machine
needs no internet, no pip and no Podman:

- its own Python (uv-managed standalone build, `_python=3.12`), so Arch's
  rolling Python cannot break it;
- PyTorch with the CUDA libraries inside the wheels (`_backend=cu130`;
  only the NVIDIA driver, `nvidia-utils`, comes from the system);
- ComfyUI at the release tag `v$pkgver`, and the custom nodes of
  `wiamox-comfyui-cuda/nodes.txt` (pinned by commit; ComfyUI-Manager is
  left out on purpose, it is online-only).

Needs `uv` and `git` (installed by `--syncdeps`) and internet **at build
time only**; the build is large (about 10 GB of wheels, 10-30 minutes).
`check()` starts the finished environment on the CPU and waits for
ComfyUI's web server; a package that cannot start is not built, and nodes
that fail to import are listed as a warning. The exact package versions are
saved in `/usr/share/doc/wiamox-comfyui-cuda/requirements.lock`. If the
library check complains about the bundled wheels, try `--no-libcheck`.

AI Center runs `/usr/bin/wiamox-comfyui` (port 8188, loopback) with
`--base-directory ~/aihub/comfyui`; models are the user's files in
`~/aihub/models/comfyui`. New ComfyUI version: change `pkgver`, `pkgrel=1`.
New/changed node: edit `nodes.txt`, bump `pkgrel`. ROCm later = a copy of
the folder as `wiamox-comfyui-rocm` with `_backend=rocm7.2`. Must be in
woxKitchen (and in the Calamares "AI" bundle) before users can run the
ComfyUI card.

## Building wed

```sh
scripts/build.sh wed
```

Builds the committed version recorded in the `wed/` submodule. Needs
internet (Rust crates, the private `wiamoxxx/floem` fork over SSH, grammars
and plugins pinned in wed's `packaging/runtime.lock`); takes about 13 minutes
and up to ~5 GB of RAM. `check()` runs wed's offline check. To build a newer
wed: bump `version` in wed's `Cargo.toml`, push, then
`git submodule update --remote wed` here and commit.

## Building woxed

```sh
scripts/build.sh woxed
```

Builds the pinned version recorded in the `woxed/` submodule. Needs
internet (Neovim, about 33 plugin repos, treesitter parsers) and runs
Woxed's offline self-check. The downloads are kept in `build/sources/`,
so later builds are faster. Too little memory while the parsers compile:
`WOXED_JOBS=2 scripts/build.sh woxed`.

**Building a newer woxed:** bump `WOXED_VERSION` in woxed's `versions.env`
(pacman only updates on a higher version) and push it. Then, here:

```sh
git submodule update --remote woxed
git commit -am "Bump woxed to <version>"
scripts/build.sh woxed
```

To put it on the ISO, `woxed` must be listed in woxclean1's
`packages.x86_64` (it is).

## Building calamares (the installer program)

`calamares-wiamox` depends on `calamares`, the installer program itself.
It is not in Arch's repos, so it is built from the AUR:

```sh
scripts/build.sh calamares
```

- The first run clones the AUR recipe into `aur/calamares/` and asks you
  to read its `PKGBUILD` before building. AUR recipes are written by other
  people.
- Every later run fetches the AUR recipe, shows what changed since the
  last build, and asks again before building.
- **Rebuild it after every Python update in Arch** (e.g. 3.14 → 3.15),
  and after new boost, yaml-cpp or kpmcore versions. It links against
  `libpython3.X`; an old build fails on the ISO with
  `libpython3.12.so.1.0: cannot open shared object file`. The version
  number stays the same for such a rebuild, so use `--force`:

  ```sh
  scripts/build.sh calamares --force
  ```

  pacman won't give that rebuild to already installed systems (same
  version). That only matters once woxKitchen is published.
- Match the ISO: build on a machine with the same package versions as
  the ISO. `pacman.conf` in woxclean1 has the `*-testing` repos on, so
  run `pacman -Syu` here first and compare `python --version` on both.

The home-folder trap that broke calamares (a `~/.local/bin/python3.12`
from `uv` was found first by CMake) is what the clean environment and
the library check above prevent. If you ever build a package with plain
`makepkg` outside this script, check the build log for
`Found Python3: /usr/bin/python3...` and run
`ldd /usr/bin/<program> | grep 'not found'` after installing it.

## Building coreutils

Works like the kernel: you keep a coreutils source tree on your disk, edit
the code there, and build it.

```sh
scripts/build.sh coreutils              # build, then add to woxKitchen
scripts/build.sh coreutils --install    # ... and install it on this machine
```

**The source tree** (`WIAMOX_COREUTILS_SRC` in `local.conf`), one of:

- **A release tarball, unpacked.** Simplest: it has `./configure` and the
  translations.
  ```sh
  mkdir -p ~/wiamox-coreutils && cd ~/wiamox-coreutils
  curl -O https://ftp.gnu.org/gnu/coreutils/coreutils-9.12.tar.xz
  curl -O https://ftp.gnu.org/gnu/coreutils/coreutils-9.12.tar.xz.sig
  gpg --verify coreutils-9.12.tar.xz.sig     # key 6C37DC12121A5006BC1DB804DF6FD971306037D9
  tar xf coreutils-9.12.tar.xz
  ```
- **A git clone**, if you want git to track your changes:
  ```sh
  git clone --recurse-submodules https://git.savannah.gnu.org/git/coreutils.git
  cd coreutils && git checkout v9.12 && git submodule update
  ```
  The build runs `./bootstrap` on it without network. Such a build has no
  translations (commands are English only).

What happens:

1. `pkgver` is read from your tree (`build-aux/git-version-gen`): `9.12`
   for a tarball, e.g. `9.12.15.a1b2c` for a clone 15 commits past `v9.12`.
2. Your tree is copied into the build folder, without `.git` and `*.o`,
   then cleaned with `make distclean`. **Your own tree is never changed**,
   so you can keep editing and test-compiling in it.
3. It is configured and built the way Arch builds coreutils
   (`--prefix=/usr --libexecdir=/usr/lib --with-openssl`, no LTO, same
   dependencies), and the test suite runs. Failed tests give a warning
   with the log path; they don't stop the build.
4. The package is called `coreutils` and replaces Arch's: `[custom]` comes
   before `[core]`, so the ISO and the offline repo take yours.

**Rebuilding the same version:** after editing the code without a new
coreutils version, raise `pkgrel` in `coreutils/PKGBUILD` (1 → 2). Like for
the kernel, `build.sh` refuses to overwrite a version woxKitchen already
has (`--force` to override).

**Keep it current.** Your coreutils stays on the ISO even when Arch
releases a newer one, with fixes. Move your changes to new coreutils
versions now and then with `coreutils/apply-patches.sh` (see
[Your own edits as patches](#your-own-edits-as-patches-kernel-coreutils)).
Arch sometimes carries its own fixes on top of a release (their recipe's
`*.patch` files); apply those to your tree too if you want them.

**It is a core package.** A broken coreutils breaks booting and logging
in. Install it on the build machine or in a VM first
(`sudo pacman -U out/coreutils-*.pkg.tar.zst`) and try a few commands.

## Your own edits as patches (kernel, coreutils)

The source trees on your disk are not in any git repo of WiamOX, and a new
upstream version is a fresh tree. So every WiamOX change to the kernel or
coreutils is **also kept here as a patch file**, and a script puts them
into a new tree:

| Package | Patches | Script | Current patches |
|---|---|---|---|
| `linux` | `linux/patches/*.patch` | `linux/apply-patches.sh <tree>` | `0001` `uname -s` = WiamOX |
| `coreutils` | `coreutils/patches/*.patch` | `coreutils/apply-patches.sh <tree>` | `0001` status messages (ls, cp, mv, ...), `0002` uname/arch authors, `0003` `uname -o` = WiamOX |

**The build never applies them.** `build.sh` compiles exactly the tree in
`WIAMOX_KERNEL_SRC` / `WIAMOX_COREUTILS_SRC`. Applying the patches is a
step you do once per new tree.

### Moving to a new upstream version

Example: coreutils 9.13 (the kernel works the same with a kernel.org
tarball and `linux/apply-patches.sh`).

```sh
cd ~/wiamox-coreutils
curl -O https://ftp.gnu.org/gnu/coreutils/coreutils-9.13.tar.xz
curl -O https://ftp.gnu.org/gnu/coreutils/coreutils-9.13.tar.xz.sig
gpg --verify coreutils-9.13.tar.xz.sig && tar xf coreutils-9.13.tar.xz

~/Projects/wiamox-pkgs/coreutils/apply-patches.sh ~/wiamox-coreutils/coreutils-9.13
```

The script goes through the patches in order and prints one line each:

- `applied:` the patch was put into the tree.
- `already applied:` the tree has it already (running the script twice is
  safe).
- `DOES NOT APPLY:` upstream changed those lines. The script stops and
  **nothing of that patch** was applied. Make the change by hand in the
  tree, then refresh the patch file (below) and run the script again.

Then set `WIAMOX_COREUTILS_SRC` (or `WIAMOX_KERNEL_SRC`) in `local.conf`
to the new tree and build. A new version starts at `pkgrel=1`.

```sh
wiamox-build coreutils      # or: scripts/build.sh coreutils inside the box
```

Check the result: `uname -o` (coreutils) / `uname -s` (kernel) print
`WiamOX`, and the status message shows after `mkdir x` in a terminal but
not in `echo "$(mkdir y)"`.

### Adding or changing an edit

1. Edit the file in your tree. Keep a pristine copy of the same version
   to diff against (an unpacked tarball, or `git diff` in a clone).
2. Write the patch, paths starting with `a/` and `b/` from the tree root:
   ```sh
   # tarball: pristine copy next to your tree
   cd ~/wiamox-coreutils
   diff -u coreutils-9.13.orig/src/ls.c coreutils-9.13/src/ls.c |
     sed '1s|^--- [^/]*/|--- a/|; 2s|^+++ [^/]*/|+++ b/|' > /tmp/new.patch
   # git clone
   git -C ~/wiamox-coreutils/coreutils diff -- src/ls.c > /tmp/new.patch
   ```
3. Put it in `coreutils/patches/` (or `linux/patches/`) with the next
   number, e.g. `0004-ls-something.patch`, and start it with a short
   header like the existing ones (`From:`, `Subject:`, why, which version
   it was made against, then `---`). Text above the first `---` line is
   ignored by `patch`.
4. Test: `apply-patches.sh` on a pristine copy must print `applied:` for
   every patch, and a second run `already applied:`.
5. Commit the patch in wiamox-pkgs. A rebuild of the same upstream version
   needs a `pkgrel` bump.

To change an existing patch, replace its file with a fresh diff of the
whole change (pristine vs. your tree) and keep the number.

**coreutils: only touch `src/`.** A release tarball comes with a
pre-generated `configure`, so edits to `m4/` or `configure.ac` do nothing
there, and in a git clone `git submodule update` throws away edits inside
`gnulib/`. That is why `uname -o` is set in `src/uname.c` (patch 0003) and
not in gnulib's `m4/host-os.m4`.

## Publishing woxKitchen online

```sh
scripts/publish.sh --dry-run   # show what would change
scripts/publish.sh             # upload
```

The release `x86_64` of this GitHub repository becomes a pacman repo:
it holds the package files plus `woxkitchen.db` / `woxkitchen.files`.
Any machine can then use it:

```ini
# above [core], see "Why the kernel package is called linux"
[woxkitchen]
SigLevel = Optional TrustAll
Server = https://github.com/wiamoxxx/wiamox-pkgs/releases/download/x86_64
```

What `publish.sh` does:

1. Takes the packages woxKitchen's database lists (the current version
   of each; old files lying in the folder are ignored).
2. Builds a fresh database for them under the name `woxkitchen`.
3. Uploads only packages that are new or changed (it keeps checksums in
   `woxkitchen.sha256`), then the database, then removes old versions
   from the release. Packages go up before the database, so the online
   database never lists a file that is not there yet.
4. Downloads the database again and checks that every package in it can
   be downloaded.

Once per machine: `pacman -S github-cli` and `gh auth login`.

**The repository must be public.** pacman cannot log in to GitHub, so
release files of a private repository cannot be downloaded; `publish.sh`
stops with a message in that case. Either make this repository public or
publish to a separate public one (`WIAMOX_PUBLISH_REPO` in `local.conf`).

The normal flow:

```sh
scripts/build.sh linux            # -> woxKitchen
scripts/build.sh calamares        # (when the AUR recipe or Python changed)
scripts/build.sh calamares-wiamox
scripts/build.sh woxed
scripts/build.sh coreutils        # after editing your coreutils tree
# build the ISO with woxKitchen (local mode), test it
scripts/publish.sh                # -> online, for everyone else
```

## Why the kernel package is called `linux`

It replaces Arch's kernel, so nothing else (package lists, boot entries,
`mkinitcpio` presets, the installer) needs to change. The rule that comes
with it: **the WiamOX repo must be listed before `[core]`** in every
`pacman.conf`, otherwise pacman takes Arch's `linux` instead.

`linux` provides `VIRTUALBOX-GUEST-MODULES`, `WIREGUARD-MODULE` and
`NTSYNC-MODULE` like Arch's kernel, so packages that depend on those
(e.g. `virtualbox-guest-utils-nox`) don't pull Arch's kernel back in.
