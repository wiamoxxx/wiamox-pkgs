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
# there is none yet. It is the file custom.db points to, because that is
# the one pacman reads. Stops when there is more than one database:
# repo-add points custom.db at whichever it wrote last, and pacman then
# silently ignores every package that is only in the other one. (That is
# how the ISO once got Arch's kernel instead of the one in woxKitchen.)
kitchen_db() {
  local base=$WIAMOX_KITCHEN/$WIAMOX_KITCHEN_DB ext dbs=() target
  for ext in zst xz gz bz2; do
    [[ ! -e $base.db.tar.$ext ]] || dbs+=("$base.db.tar.$ext")
  done
  if (( ${#dbs[@]} > 1 )); then
    die "woxKitchen has more than one database:
$(printf '        %s\n' "${dbs[@]}")
    pacman only reads $base.db (-> $(readlink "$base.db" 2>/dev/null || echo '?')) and ignores
    every package that is only in the other one. Build one database from the
    package files (delete old versions of a package first):
        cd $WIAMOX_KITCHEN
        rm -f $WIAMOX_KITCHEN_DB.db* $WIAMOX_KITCHEN_DB.files*
        repo-add $WIAMOX_KITCHEN_DB.db.tar.zst *.pkg.tar.zst"
  fi
  if [[ -L $base.db ]]; then
    target=$(readlink -f "$base.db")
    [[ -e $target ]] || die "$base.db points to $target, which does not exist."
    echo "$target"
  elif (( ${#dbs[@]} )); then
    echo "${dbs[0]}"
  fi
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

# Clones a package recipe (git URL $3) into $1, or updates the existing
# clone, and shows every change since the last build. $2 is the package
# name, $4 where it comes from ("the AUR", "Arch"). AUR recipes are written
# by other people: with $5 = ask, a new recipe and every change must be
# confirmed before anything is built.
recipe_update() {
  local dir=$1 name=$2 url=$3 from=$4 ask=${5-} old new
  command -v git >/dev/null || die "git not found."
  if [[ ! -d $dir/.git ]]; then
    msg "Cloning $name from $from into $dir ..."
    mkdir -p "$(dirname "$dir")"
    git clone --quiet "$url" "$dir" ||
      { rm -rf "$dir"; die "Could not clone $url."; }
    [[ -f $dir/PKGBUILD ]] || { rm -rf "$dir"; die "$from has no package called $name."; }
    if [[ $ask == ask ]]; then
      msg "First build of $name from $from. Read $dir/PKGBUILD before continuing."
      confirm "Build $name?"
    fi
    return
  fi

  old=$(git -C "$dir" rev-parse HEAD)
  git -C "$dir" fetch --quiet origin
  new=$(git -C "$dir" rev-parse '@{upstream}')
  if [[ $old == "$new" ]]; then
    msg "$name: recipe from $from unchanged since the last build."
    return
  fi
  msg "$name: the recipe from $from changed since the last build:"
  git -C "$dir" --no-pager log --oneline "$old..$new"
  git -C "$dir" --no-pager diff "$old" "$new" -- . ':!.SRCINFO'
  [[ $ask != ask ]] || confirm "Build $name with these changes?"
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
