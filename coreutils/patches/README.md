# WiamOX patches for coreutils

Every `*.patch` file here is applied to the coreutils source, in name
order, after Arch's own `prepare()`. Name them `0001-short-name.patch`,
`0002-...`.

Make a patch from an unpacked source tree:

```sh
cd ~/wiamox-pkgs/build/coreutils/src/coreutils-*/   # after one build, or unpack the tarball
git init -q && git add -A && git commit -qm base
# ... edit the files ...
git diff > ~/wiamox-pkgs/coreutils/patches/0001-short-name.patch
```

`git diff` writes `a/` and `b/` paths, which `patch -p1` expects.
