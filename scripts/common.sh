# Shared by the scripts in this folder. Source it, don't run it.
# shellcheck shell=bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

msg() { echo "==> $*"; }
warn() { echo "==> WARNING: $*" >&2; }
die() { echo "==> ERROR: $*" >&2; exit 1; }

# Reads local.conf; WIAMOX_* variables already set in the environment win.
load_conf() {
  local env_vars saved=""
  env_vars=$(compgen -v WIAMOX_ || true)
  # shellcheck disable=SC2086  # $env_vars is a list of names
  [[ -z $env_vars ]] || saved=$(declare -p $env_vars | sed 's/^declare /declare -g /')
  if [[ -r $ROOT/local.conf ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/local.conf"
  fi
  eval "$saved"
  WIAMOX_KITCHEN_DB=${WIAMOX_KITCHEN_DB:-custom}
}

# The woxKitchen database file (custom.db.tar.zst, ...); prints nothing if
# there is none yet.
kitchen_db() {
  local ext
  for ext in zst xz gz bz2; do
    if [[ -e $WIAMOX_KITCHEN/$WIAMOX_KITCHEN_DB.db.tar.$ext ]]; then
      echo "$WIAMOX_KITCHEN/$WIAMOX_KITCHEN_DB.db.tar.$ext"
      return
    fi
  done
}

# Keeps everything from your home folder out of the build. A Python in
# ~/.local/bin (uv, pyenv, ...) or an active virtualenv is otherwise found
# first by CMake/meson, and the package then needs a libpython that exists
# only in your home folder. calamares built that way fails with
# "libpython3.12.so.1.0: cannot open shared object file".
clean_build_env() {
  local dir kept=() dropped=() var
  local -a parts
  IFS=: read -ra parts <<<"$PATH"
  for dir in "${parts[@]}"; do
    case $dir in
      "" | . | "$HOME" | "$HOME"/*) dropped+=("${dir:-(empty)}") ;;
      *) kept+=("$dir") ;;
    esac
  done
  PATH=$(IFS=:; echo "${kept[*]}")
  export PATH

  for var in VIRTUAL_ENV CONDA_PREFIX PYTHONHOME PYTHONPATH PYTHONUSERBASE \
             LD_LIBRARY_PATH LD_PRELOAD PKG_CONFIG_PATH CMAKE_PREFIX_PATH; do
    if [[ -n ${!var-} ]]; then
      dropped+=("\$$var")
      unset "$var"
    fi
  done
  # Python modules installed with pip --user stay out too.
  export PYTHONNOUSERSITE=1

  if (( ${#dropped[@]} )); then
    msg "Building without (from your home folder / environment): ${dropped[*]}"
  fi
}

# Asks before building, when someone is at the keyboard.
confirm() {
  [[ -t 0 ]] || return 0
  local answer
  read -rp "==> $1 [y/N] " answer
  [[ $answer == [yY]* ]] || die "Stopped."
}

# Clones an AUR package into $1 (name $2), or updates the existing clone.
# AUR recipes are written by other people: new ones and every change since
# the last build are shown before anything is built.
aur_update() {
  local dir=$1 name=$2 old new
  command -v git >/dev/null || die "git not found."
  if [[ ! -d $dir/.git ]]; then
    msg "Cloning $name from the AUR into $dir ..."
    git clone --quiet "https://aur.archlinux.org/$name.git" "$dir"
    [[ -f $dir/PKGBUILD ]] || { rm -rf "$dir"; die "The AUR has no package called $name."; }
    msg "First build of $name from the AUR. Read $dir/PKGBUILD before continuing."
    confirm "Build $name?"
    return
  fi

  old=$(git -C "$dir" rev-parse HEAD)
  git -C "$dir" fetch --quiet origin
  new=$(git -C "$dir" rev-parse '@{upstream}')
  if [[ $old == "$new" ]]; then
    msg "$name: AUR recipe unchanged since the last build."
    return
  fi
  msg "$name: the AUR recipe changed since the last build:"
  git -C "$dir" --no-pager log --oneline "$old..$new"
  git -C "$dir" --no-pager diff "$old" "$new" -- . ':!.SRCINFO'
  confirm "Build $name with these changes?"
  git -C "$dir" merge --quiet --ff-only "$new"
}

# Checks every program and shared library in the given package files:
# each library it needs must exist on this machine (or come with the
# packages themselves), and none may be loaded from /home. Prints the
# problems; returns 1 if there are any.
check_libs() {
  local tmp f rel out bad line lib_path problems=0 magic
  tmp=$(mktemp -d)
  for f in "$@"; do
    bsdtar -xf "$f" -C "$tmp" --exclude '.PKGINFO' --exclude '.BUILDINFO' \
      --exclude '.MTREE' --exclude '.INSTALL'
  done
  # Libraries shipped in the packages count as present.
  lib_path=$(find "$tmp" -type f -name '*.so*' -printf '%h\n' | sort -u | paste -sd:)

  while IFS= read -r -d '' f; do
    LC_ALL=C IFS= read -r -n4 -d '' magic <"$f" || true
    [[ $magic == $'\x7fELF' ]] || continue
    # ldd exits non-zero both for missing libraries and for files it can't
    # handle (static programs, other architectures); only its output counts.
    out=$(LD_LIBRARY_PATH=$lib_path ldd -- "$f" 2>/dev/null || true)
    bad=$(grep -E 'not found|=> /home/' <<<"$out" || true)
    [[ -n $bad ]] || continue
    rel=${f#"$tmp"}
    echo "==> $rel:" >&2
    while read -r line; do echo "      $line"; done <<<"$bad" >&2
    problems=$((problems + 1))
  done < <(find "$tmp" -type f \( -perm -u+x -o -name '*.so' -o -name '*.so.*' \) -print0)

  chmod -R u+w "$tmp"
  rm -rf "$tmp"
  (( problems == 0 ))
}
