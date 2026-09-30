# wiamox-pkgs

The WiamOX packages that don't come from Arch, as build recipes (PKGBUILDs),
the script that builds them into your local woxKitchen repo, and the
script that publishes woxKitchen online as the pacman repo `[woxkitchen]`.

| Folder | Package | Source |
|---|---|---|
| `linux/` | `linux`, `linux-headers`: the WiamOX kernel | a kernel source tree **on your disk** (with your own edits) |
| `calamares-wiamox/` | `calamares-wiamox`: installer branding and config | git submodule → [wiamoxxx/calamares-wiamox](https://github.com/wiamoxxx/calamares-wiamox) |

Finished packages go to `out/`, build logs to `build/logs/`.

## Setup (once per machine)

```sh
cp local.conf.example local.conf
$EDITOR local.conf        # WIAMOX_KERNEL_SRC, WIAMOX_KITCHEN, ...
```

Build machine: Arch-based, with `base-devel` installed. Everything else
the kernel needs (`bc cpio gettext libelf pahole perl python tar xz zstd`)
is installed by makepkg when missing. Space: about **30 GB** free where
it compiles (`build/` here, or `WIAMOX_BUILDDIR`), because the config
has full debug info (needed for BTF).

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

## The `calamares` program (AUR, built by hand)

`calamares-wiamox` depends on `calamares`, the installer program itself.
It is not in Arch's repos and has no recipe here: build it from the AUR
and add it to woxKitchen yourself. Full steps are in the calamares-wiamox
README, section "The `calamares` program itself". In short:

- **Rebuild it after every Python version change in Arch** (and after new
  boost, yaml-cpp or kpmcore versions). It links against `libpython3.X`,
  and an old build fails on the ISO with
  `libpython3.12.so.1.0: cannot open shared object file`.
- **Don't let your home folder into the build.** A second Python in
  `~/.local/bin` (e.g. from `uv python install`) is found first by CMake,
  and the package then needs a `libpython` that exists only in your home
  folder. Build in a clean chroot (`extra-x86_64-build`, or
  `extra-testing-x86_64-build` while the ISO uses the testing repos) or
  with `env PATH=/usr/local/sbin:/usr/local/bin:/usr/bin makepkg -Csrf`.
  The build log must show `Found Python3: /usr/bin/python3...`.
- Start from a clean folder (`rm -rf src pkg *.pkg.tar.zst`). makepkg
  otherwise reuses the old `src/` build or refuses to overwrite an
  existing package.
- Check before `repo-add`: `ldd /usr/bin/calamares | grep -E 'python|not found'`
  shows the libpython from `/usr/lib` and no "not found".

The same home-folder trap can hit any package built with plain
`makepkg` on the build machine. Packages that go on the ISO are safest
when built in a clean chroot.

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
