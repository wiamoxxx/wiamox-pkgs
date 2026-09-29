# wiamox-pkgs

The WiamOX packages that don't come from Arch, as build recipes (PKGBUILDs),
and the script that builds them into your local woxKitchen repo.

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

## Why the kernel package is called `linux`

It replaces Arch's kernel, so nothing else (package lists, boot entries,
`mkinitcpio` presets, the installer) needs to change. The rule that comes
with it: **the WiamOX repo must be listed before `[core]`** in every
`pacman.conf`, otherwise pacman takes Arch's `linux` instead.

`linux` provides `VIRTUALBOX-GUEST-MODULES`, `WIREGUARD-MODULE` and
`NTSYNC-MODULE` like Arch's kernel, so packages that depend on those
(e.g. `virtualbox-guest-utils-nox`) don't pull Arch's kernel back in.
