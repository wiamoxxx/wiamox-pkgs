#!/bin/bash
# Re-apply WiamOX's own kernel edits (linux/patches/*.patch, in order) to a
# kernel source tree, e.g. a fresh kernel.org tarball for a version bump:
#
#   tar -xf linux-7.4.tar.xz && linux/apply-patches.sh linux-7.4
#   then point WIAMOX_KERNEL_SRC (local.conf) at it and run build.sh linux
#
# The build itself never applies these: it compiles whatever the tree in
# WIAMOX_KERNEL_SRC contains (CLAUDE.md, Decisions). Patches the tree
# already has are skipped; one that does not fit stops the script, nothing
# of it is applied (fix it by hand, then refresh the .patch file).
set -euo pipefail

tree=${1:?usage: ${0##*/} <kernel source tree>}
[[ -f $tree/Makefile && -d $tree/include/linux ]] ||
  { echo "${0##*/}: $tree is not a kernel source tree" >&2; exit 1; }
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
