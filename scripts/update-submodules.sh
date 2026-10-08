#!/usr/bin/env bash
# Moves the submodules (calamares-wiamox, woxed, ai-center, ...) to the
# newest commit of their branch (.gitmodules, default main), so you do not
# have to run `git submodule update --remote` for each one. New submodules
# in .gitmodules are picked up automatically.
#
#   scripts/update-submodules.sh                  update all, stage the new pins
#   scripts/update-submodules.sh --dry-run        only show what would change
#   scripts/update-submodules.sh --commit         update all and commit the pins
#   scripts/update-submodules.sh ai-center woxed  only these
#
# Empty submodules (after a plain git clone) are cloned first. A submodule
# with uncommitted changes is skipped, never overwritten. Nothing is pushed.
# After an update, build the package (scripts/build.sh <name>): the version
# shown is the pkgver/pkgrel of its PKGBUILD; woxKitchen refuses a version it
# already has, so bump it in the submodule's own repo if it is unchanged.
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

dry=0
commit=0
wanted=()
for arg in "$@"; do
  case $arg in
    --dry-run) dry=1 ;;
    --commit) commit=1 ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $arg" >&2; usage 1 ;;
    *) wanted+=("${arg%/}") ;;
  esac
done
(( !(dry && commit) )) || die "--dry-run and --commit do not go together."

cd "$ROOT"
[[ -f .gitmodules ]] || die "No .gitmodules in $ROOT."

# name<TAB>path for every submodule in .gitmodules
mapfile -t all < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' |
  sed -E 's/^submodule\.(.*)\.path (.*)$/\1\t\2/')
(( ${#all[@]} )) || die "No submodules in .gitmodules."

# Which ones: all, or the named ones (by name or folder).
todo=()
if (( ${#wanted[@]} == 0 )); then
  todo=("${all[@]}")
else
  for w in "${wanted[@]}"; do
    found=0
    for entry in "${all[@]}"; do
      if [[ $w == "${entry%%$'\t'*}" || $w == "${entry##*$'\t'}" ]]; then
        todo+=("$entry"); found=1
      fi
    done
    (( found )) || die "'$w' is not a submodule (see .gitmodules)."
  done
fi

# The version a PKGBUILD in <path> has at <commit>.
pkg_version() {
  git -C "$1" show "$2:PKGBUILD" 2>/dev/null |
    awk -F= '$1=="pkgver"{v=$2} $1=="pkgrel"{r=$2} END{if (v!="" && v !~ /\$/) print v "-" (r==""?1:r)}'
}

updated=()
summary=()
for entry in "${todo[@]}"; do
  name=${entry%%$'\t'*}
  path=${entry##*$'\t'}
  branch=$(git config -f .gitmodules --get "submodule.$name.branch" || true)
  branch=${branch:-main}

  # The pin as staged (what the next commit would record), so a second run
  # before committing says "up to date".
  old=$(git ls-files -s -- "$path" | awk '$1=="160000"{print $2}')
  [[ -n $old ]] || { warn "$name: not recorded as a submodule, skipped."; continue; }

  if [[ ! -e $path/.git ]]; then
    msg "$name: cloning ..."
    git submodule update --init -- "$path" >/dev/null ||
      { warn "$name: clone failed (private repo? try: gh auth login && gh auth setup-git), skipped."; summary+=("$name: FAILED (clone)"); continue; }
  fi
  if [[ -n $(git -C "$path" status --porcelain) ]]; then
    warn "$name: has uncommitted changes, skipped. Commit or stash them there first."
    summary+=("$name: skipped (uncommitted changes)")
    continue
  fi

  git -C "$path" fetch -q origin "$branch" ||
    { warn "$name: could not fetch origin/$branch, skipped."; summary+=("$name: FAILED (fetch)"); continue; }
  new=$(git -C "$path" rev-parse FETCH_HEAD)

  if [[ $new == "$old" ]]; then
    summary+=("$name: up to date (${old:0:7}, ${branch})")
    continue
  fi

  count=$(git -C "$path" rev-list --count "$old..$new" 2>/dev/null || echo '?')
  oldver=$(pkg_version "$path" "$old")
  newver=$(pkg_version "$path" "$new")
  line="$name: ${old:0:7} -> ${new:0:7} ($count new commits on $branch)"
  [[ -z $newver ]] || line+=", PKGBUILD ${oldver:-?} -> $newver"
  summary+=("$line")
  msg "$line"
  git -C "$path" log --oneline --no-decorate -n 8 "$old..$new" 2>/dev/null | sed 's/^/      /' || true

  (( dry )) && continue
  git -C "$path" checkout -q --detach "$new"
  git add -- "$path"
  updated+=("$path")
done

echo
msg "Summary:"
printf '    %s\n' "${summary[@]}"

if (( dry )); then
  msg "Dry run: nothing was changed."
elif (( ${#updated[@]} == 0 )); then
  msg "No pins changed."
elif (( commit )); then
  names=$(printf '%s, ' "${updated[@]}")
  git commit -q -m "Update submodules: ${names%, }" -- "${updated[@]}"
  msg "Committed the new pins (not pushed)."
else
  msg "New pins are staged. Commit them: git commit -m 'Update submodules'"
fi
