# WiamOX patches for coreutils

Every `*.patch` file here is applied to the coreutils source, in name
order, after Arch's own `prepare()` (which runs `./bootstrap` and applies
Arch's patches). Name them `0001-short-name.patch`, `0002-...`.

Make a patch after one build of `scripts/build.sh coreutils`. The source
is a git checkout of coreutils, with Arch's and the existing WiamOX patches
already applied:

```sh
cd ~/wiamox-pkgs/build/coreutils/src/coreutils
git add -A && git commit -qm base     # snapshot, so the diff only shows your change
# ... edit files, e.g. src/ls.c ...
git diff > ~/wiamox-pkgs/coreutils/patches/0002-short-name.patch
```

Then raise `WIAMOX_PKGREL` in `../wiamox.conf` (unless Arch's version just
changed) and build again.

Patches to C sources and docs are fine. A patch to `configure.ac` or
`Makefile.am` lands after `./bootstrap` has run; check the build log if
you need one.
