# Sourced by ../scripts/build.sh and PKGBUILD. Source it, don't run it.
# shellcheck shell=bash

# Prints the 7.3 kernel source tree to use. $1 is what you configured
# (WIAMOX_KERNEL73_SRC): the tree itself, or a folder like ~/Sources that
# holds it. A folder without a Makefile is searched for linux-7.3* (newest
# version wins, so linux-7.3.2 beats linux-7.3.1 beats linux-7.3-rc4).
# Prints nothing and fails if there is no tree.
_wox_find_kernel73_src() {
  local want=${1%/} d found=""
  [[ -n $want ]] || return 1
  if [[ -f $want/Makefile && -d $want/kernel ]]; then
    echo "$want"
    return 0
  fi
  for d in "$want"/linux-7.3* "$(dirname "$want")"/linux-7.3*; do
    [[ -f $d/Makefile && -d $d/kernel ]] || continue
    found+="$d"$'\n'
  done
  [[ -n $found ]] || return 1
  # sort -V puts 7.3-rc4 after 7.3.1; take the last that is not an rc unless only rcs exist.
  local nonrc
  nonrc=$(grep -v -- '-rc' <<<"$found" | sort -uV | tail -n1)
  if [[ -n $nonrc ]]; then echo "$nonrc"; else sort -uV <<<"$found" | tail -n1; fi
}
