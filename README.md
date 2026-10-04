# wiamox-pkgs

The WiamOX packages that don't come from Arch, as build recipes (PKGBUILDs),
the script that builds them into your local woxKitchen repo, and the
script that publishes woxKitchen online as the pacman repo `[woxkitchen]`.

| Folder | Package | Source |
|---|---|---|
| `linux/` | `linux`, `linux-headers`: the WiamOX kernel | a kernel source tree **on your disk** (with your own edits) |
| `calamares-wiamox/` | `calamares-wiamox`: installer branding and config | git submodule → [wiamoxxx/calamares-wiamox](https://github.com/wiamoxxx/calamares-wiamox) |
| `ai-center/` | `ai-center`: WiamOX AI Center (local AI launcher: llama.cpp via Podman, ComfyUI, ACE-Step, OpenCode) | git submodule → [wiamoxxx/ai-center](https://github.com/wiamoxxx/ai-center) |
| `woxed/` | `woxed`: the WiamOX Editor | git submodule → [wiamoxxx/woxed](https://github.com/wiamoxxx/woxed) |
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
  package needs to build is installed by makepkg when missing.
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
launcher only (arch `any`, needs `podman`, `python-textual`,
`python-tomlkit` from Arch). Models, container images and GPU setup are
per-user data, not part of the package. Run it with `wiamox-ai-center`.
To put it on the ISO, `ai-center` must be listed in woxclean1's
`packages.x86_64`. Newer version: change it in its own repo, bump
`pkgver`/`pkgrel`, then `git submodule update --remote ai-center`, commit,
build.

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
versions now and then. Arch sometimes carries its own fixes on top of a
release (their recipe's `*.patch` files); apply those to your tree too if
you want them.

**It is a core package.** A broken coreutils breaks booting and logging
in. Install it on the build machine or in a VM first
(`sudo pacman -U out/coreutils-*.pkg.tar.zst`) and try a few commands.

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
