#!/bin/bash
# Re-apply WiamOX's own coreutils edits (coreutils/patches/*.patch, in
# order) to a coreutils source tree, e.g. a fresh release tarball or git
# clone for a version bump:
#
#   tar -xf coreutils-9.13.tar.xz && coreutils/apply-patches.sh coreutils-9.13
#   then point WIAMOX_COREUTILS_SRC (local.conf) at it and run build.sh coreutils
#
# The patches only touch src/, so a release tarball and a git clone take
# them the same way. The build itself never applies these: it compiles
# whatever the tree in WIAMOX_COREUTILS_SRC contains (CLAUDE.md, Decisions).
# Patches the tree already has are skipped; one that does not fit stops the
# script, nothing of it is applied (fix it by hand, then refresh the .patch file).
set -euo pipefail

tree=${1:?usage: ${0##*/} <coreutils source tree>}
[[ -f $tree/configure.ac && -f $tree/src/coreutils.c ]] ||
  { echo "${0##*/}: $tree is not a coreutils source tree" >&2; exit 1; }
patches=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/patches

shopt -s nullglob
for p in "$patches"/*.patch; do
  name=${p##*/}
  if patch -d "$tree" -p1 -R --dry-run --silent <"$p" >/dev/null 2>&1; then
    echo "already applied: $name"
  elif patch -d "$tree" -p1 --forward --dry-run --silent <"$p" >/dev/null 2>&1; then
    patch -d "$tree" -p1 --forward --silent --no-backup-if-mismatch <"$p"
    echo "applied:         $name"
  else
    echo "DOES NOT APPLY:  $name (changed upstream?); nothing of it was applied" >&2
    exit 1
  fi
done
