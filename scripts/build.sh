#!/usr/bin/env bash
# Builds one package of this repo with makepkg and adds it to your local
# woxKitchen repo, ready for the ISO build (woxclean1) to pick up.
#
#   scripts/build.sh linux                build the kernel, add it to woxKitchen
#   scripts/build.sh linux --install      ... and install it on this machine too
#   scripts/build.sh linux --no-kitchen   only build, leave woxKitchen alone
#   scripts/build.sh linux --force        rebuild a version woxKitchen already has
#   scripts/build.sh linux-7.3            Linux 7.3 (own package, lean config), from ~/Sources
#   scripts/build.sh linux-7.3 --config-only  only make + check the 7.3 config (no compile)
#   scripts/build.sh calamares-wiamox     the installer config (git submodule)
#   scripts/build.sh woxed                the WiamOX Editor (git submodule)
#   scripts/build.sh ai-center            the WiamOX AI Center launcher (git submodule)
#   scripts/build.sh wiamox-opencode      OpenCode (offline build of the upstream binary)
#   scripts/build.sh wiamox-wox           wox why: explain failed commands with the local AI
#   scripts/build.sh wiamox-llama.cpp-cuda  llama.cpp / llama-server, CUDA build
#   scripts/build.sh wiamox-yue2.cpp-cuda   yue2.cpp / yue-server (AI music), CUDA build
#   scripts/build.sh wiamox-comfyui-cuda    ComfyUI with its own Python + PyTorch (offline), CUDA build
#   scripts/build.sh calamares            the installer program, from the AUR
#   scripts/build.sh coreutils            coreutils from your source tree
#   scripts/build.sh <pkg> --no-libcheck  skip the shared-library check
#
# Packages go to out/, logs to build/logs/. Settings come from local.conf
# in the repo root (copy local.conf.example); WIAMOX_* variables set in the
# environment win over it.
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# --- arguments ---------------------------------------------------------------
pkg=""
install=0
kitchen=1
force=0
libcheck=1
config_only=0
for arg in "$@"; do
  case $arg in
    --install) install=1 ;;
    --no-kitchen) kitchen=0 ;;
    --force) force=1 ;;
    --no-libcheck) libcheck=0 ;;
    --config-only) config_only=1 ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $arg" >&2; usage 1 ;;
    *) [[ -z $pkg ]] || usage 1; pkg=${arg%/} ;;
  esac
done
[[ -n $pkg ]] || usage 1
(( !config_only )) || [[ $pkg == linux-7.3 ]] || die "--config-only only works with linux-7.3."
if (( !config_only )); then
  [[ $EUID -ne 0 ]] || die "Run this as your normal user; makepkg refuses to run as root."
  command -v makepkg >/dev/null || die "makepkg not found (this needs an Arch-based system)."
fi
(( !config_only )) || kitchen=0

# Packages built straight from the AUR. Their recipes are not part of this
# repo: they are cloned into aur/<name> and updated on every build.
aur_packages=(calamares)
is_aur=0
for name in "${aur_packages[@]}"; do
  [[ $pkg != "$name" ]] || is_aur=1
done

if (( is_aur )); then
  pkgdir="$ROOT/aur/$pkg"
  recipe_update "$pkgdir" "$pkg" "https://aur.archlinux.org/$pkg.git" "the AUR" ask
else
  pkgdir="$ROOT/$pkg"
  # Submodules (calamares-wiamox, woxed, ai-center) are empty after a plain git clone.
  if [[ ! -f $pkgdir/PKGBUILD ]] &&
     git -C "$ROOT" config -f .gitmodules --get "submodule.$pkg.path" >/dev/null 2>&1; then
    msg "Fetching the $pkg submodule ..."
    git -C "$ROOT" submodule update --init -- "$pkg"
  fi
fi
[[ -f $pkgdir/PKGBUILD ]] || die "No PKGBUILD in $pkgdir"

# --- settings ----------------------------------------------------------------
load_conf
clean_build_env
export WIAMOX_KERNEL_SRC=${WIAMOX_KERNEL_SRC-} WIAMOX_KERNEL_CONFIG=${WIAMOX_KERNEL_CONFIG:-fragments}
export WIAMOX_COREUTILS_SRC=${WIAMOX_COREUTILS_SRC-}
export WIAMOX_KERNEL73_SRC=${WIAMOX_KERNEL73_SRC-} WIAMOX_KERNEL73_CONFIG=${WIAMOX_KERNEL73_CONFIG:-fragments}
export BUILDDIR=${WIAMOX_BUILDDIR:-$ROOT/build}
# Kept out of the package folders, so the submodules stay clean. SRCDEST
# holds downloaded sources (woxed: Neovim, ~33 plugin repos) between builds.
export PKGDEST=$ROOT/out LOGDEST=$BUILDDIR/logs SRCDEST=${SRCDEST:-$BUILDDIR/sources}
mkdir -p "$PKGDEST" "$LOGDEST" "$SRCDEST" "$ROOT/build"
if [[ -z ${MAKEFLAGS-} ]]; then
  MAKEFLAGS="-j$(nproc)"
  export MAKEFLAGS
fi

if (( kitchen )); then
  [[ -n ${WIAMOX_KITCHEN-} ]] || die "WIAMOX_KITCHEN is not set (local.conf). Use --no-kitchen to only build."
  [[ -d $WIAMOX_KITCHEN && -w $WIAMOX_KITCHEN ]] || die "woxKitchen folder '$WIAMOX_KITCHEN' does not exist or is not writable."
  command -v repo-add >/dev/null || die "repo-add not found (pacman package)."
  # Stops now, not after an hour of compiling, if woxKitchen has two databases.
  kitchen_db >/dev/null
fi

# --- Linux 7.3: own package, source found in ~/Sources ------------------------
if [[ $pkg == linux-7.3 ]]; then
  # shellcheck source=../linux-7.3/find-src.sh
  source "$pkgdir/find-src.sh"
  found_src=$(_wox_find_kernel73_src "$WIAMOX_KERNEL73_SRC") ||
    die "No Linux 7.3 source tree found. WIAMOX_KERNEL73_SRC='${WIAMOX_KERNEL73_SRC}' (set it in local.conf)
    must be the folder with the top-level Makefile, or a folder that contains linux-7.3*."
  export WIAMOX_KERNEL73_SRC=$found_src
  src_ver=$(awk -F' *= *' '
    $1 == "VERSION"      { v = $2 }
    $1 == "PATCHLEVEL"   { p = $2 }
    $1 == "SUBLEVEL"     { s = $2 }
    $1 == "EXTRAVERSION" { e = $2; exit }
    END { printf "%s.%s.%s%s\n", v, p, s, e }
  ' "$WIAMOX_KERNEL73_SRC/Makefile" | sed 's/-/./g')
  [[ $src_ver == 7.3.* ]] ||
    die "$WIAMOX_KERNEL73_SRC is Linux $src_ver, not 7.3. (For 7.2 use: build.sh linux)"
  msg "Kernel source: $WIAMOX_KERNEL73_SRC (Linux $src_ver)"

  if (( config_only )); then
    # Same steps as prepare() in linux-7.3/PKGBUILD, on a throw-away copy;
    # your source tree is not touched.
    tmp=$(mktemp -d "$BUILDDIR/config-only.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    msg "Copying the tree to $tmp ..."
    tar -C "$WIAMOX_KERNEL73_SRC" --exclude=.git --exclude='*.o' --exclude='*.ko' -cf - . | tar -C "$tmp" -xf -
    (cd "$tmp" && make -s mrproper &&
      MERGE_LOG=$tmp/merge_config.log "$pkgdir/make-config.sh" "$pkgdir" "$WIAMOX_KERNEL73_CONFIG" &&
      cp .config "$ROOT/build/linux-7.3.config")
    msg "Config written to $ROOT/build/linux-7.3.config (no kernel was compiled)."
    exit 0
  fi
fi

# --- kernel checks, before spending an hour compiling ------------------------
if [[ $pkg == linux ]]; then
  [[ -f $WIAMOX_KERNEL_SRC/Makefile ]] ||
    die "WIAMOX_KERNEL_SRC='$WIAMOX_KERNEL_SRC' is not a kernel source tree (set it in local.conf)."

  src_ver=$(awk -F' *= *' '
    $1 == "VERSION"      { v = $2 }
    $1 == "PATCHLEVEL"   { p = $2 }
    $1 == "SUBLEVEL"     { s = $2 }
    $1 == "EXTRAVERSION" { e = $2; exit }
    END { printf "%s.%s.%s%s\n", v, p, s, e }
  ' "$WIAMOX_KERNEL_SRC/Makefile" | sed 's/-/./g')
  pb_ver=$(sed -n 's/^pkgver=//p' "$pkgdir/PKGBUILD")
  pb_rel=$(sed -n 's/^pkgrel=//p' "$pkgdir/PKGBUILD")
  # makepkg resets pkgrel to 1 when pkgver() finds a new kernel version.
  [[ $src_ver == "$pb_ver" ]] && rel=$pb_rel || rel=1
  msg "Kernel source: $WIAMOX_KERNEL_SRC"
  msg "Will build: linux $src_ver-$rel (config: $WIAMOX_KERNEL_CONFIG)"

  if (( kitchen && !force )) &&
     compgen -G "$WIAMOX_KITCHEN/linux-$src_ver-$rel-x86_64.pkg.tar.*" >/dev/null; then
    die "woxKitchen already has linux $src_ver-$rel. Bump pkgrel in linux/PKGBUILD
    (otherwise pacman will not update installed systems), or use --force to replace it."
  fi

  free_gb=$(( $(df -Pk "$BUILDDIR" | awk 'NR==2 { print $4 }') / 1024 / 1024 ))
  (( free_gb >= 30 )) ||
    warn "Only ${free_gb} GB free in $BUILDDIR; a kernel build with debug info needs about 30 GB."

elif [[ $pkg == linux-7.3 ]]; then
  pb_ver=$(sed -n 's/^pkgver=//p' "$pkgdir/PKGBUILD")
  pb_rel=$(sed -n 's/^pkgrel=//p' "$pkgdir/PKGBUILD")
  # makepkg resets pkgrel to 1 when pkgver() finds a new kernel version.
  [[ $src_ver == "$pb_ver" ]] && rel=$pb_rel || rel=1
  msg "Will build: linux-7.3 $src_ver-$rel (config: $WIAMOX_KERNEL73_CONFIG)"

  if (( kitchen && !force )) &&
     compgen -G "$WIAMOX_KITCHEN/linux-7.3-$src_ver-$rel-x86_64.pkg.tar.*" >/dev/null; then
    die "woxKitchen already has linux-7.3 $src_ver-$rel. Bump pkgrel in linux-7.3/PKGBUILD
    (otherwise pacman will not update installed systems), or use --force to replace it."
  fi

  free_gb=$(( $(df -Pk "$BUILDDIR" | awk 'NR==2 { print $4 }') / 1024 / 1024 ))
  (( free_gb >= 30 )) ||
    warn "Only ${free_gb} GB free in $BUILDDIR; a kernel build with debug info needs about 30 GB."

# --- coreutils checks, same idea: the source is a folder on this machine ----
elif [[ $pkg == coreutils ]]; then
  gvg=$WIAMOX_COREUTILS_SRC/build-aux/git-version-gen
  [[ -x $gvg ]] || gvg=$WIAMOX_COREUTILS_SRC/gnulib/build-aux/git-version-gen  # fresh clone: before ./bootstrap
  [[ -f $WIAMOX_COREUTILS_SRC/configure.ac && -x $gvg ]] ||
    die "WIAMOX_COREUTILS_SRC='$WIAMOX_COREUTILS_SRC' is not a coreutils source tree (set it in local.conf)."
  # Same as pkgver() in coreutils/PKGBUILD.
  src_ver=$(cd "$WIAMOX_COREUTILS_SRC" && "$gvg" .tarball-version 2>/dev/null) || src_ver=""
  src_ver=${src_ver%-dirty}
  src_ver=${src_ver%-modified}
  [[ $src_ver =~ ^[0-9] ]] ||
    die "Cannot read the coreutils version from $WIAMOX_COREUTILS_SRC. A release tarball
    has .tarball-version; a git clone needs its .git folder and tags (git fetch --tags)."
  src_ver=${src_ver//-/.}
  if [[ ! -x $WIAMOX_COREUTILS_SRC/configure && ! -f $WIAMOX_COREUTILS_SRC/gnulib/gnulib-tool ]]; then
    die "$WIAMOX_COREUTILS_SRC is a git clone without gnulib. Run there:
    git submodule update --init"
  fi
  pb_ver=$(sed -n 's/^pkgver=//p' "$pkgdir/PKGBUILD")
  pb_rel=$(sed -n 's/^pkgrel=//p' "$pkgdir/PKGBUILD")
  # makepkg resets pkgrel to 1 when pkgver() finds a new version.
  [[ $src_ver == "$pb_ver" ]] && rel=$pb_rel || rel=1
  msg "coreutils source: $WIAMOX_COREUTILS_SRC"
  msg "Will build: coreutils $src_ver-$rel"

  if (( kitchen && !force )) &&
     compgen -G "$WIAMOX_KITCHEN/coreutils-$src_ver-$rel-x86_64.pkg.tar.*" >/dev/null; then
    die "woxKitchen already has coreutils $src_ver-$rel. Bump pkgrel in coreutils/PKGBUILD
    (otherwise pacman will not update installed systems), or use --force to replace it."
  fi
else
  # Other packages have a fixed version in their PKGBUILD.
  mapfile -t planned < <(cd "$pkgdir" && makepkg --packagelist)
  for f in "${planned[@]}"; do
    name=$(basename "$f")
    name=${name%.pkg.tar.*}
    # makepkg lists a -debug package whenever makepkg.conf enables debug,
    # even if there is nothing to put in it.
    [[ $name == *-debug-* ]] && continue
    msg "Will build: $name"
    if (( kitchen && !force )) && compgen -G "$WIAMOX_KITCHEN/$name.pkg.tar.*" >/dev/null; then
      if (( is_aur )); then
        die "woxKitchen already has $name. To rebuild the same AUR version (e.g. after a
    Python update in Arch), use --force to replace it."
      fi
      die "woxKitchen already has $name. Bump pkgver or pkgrel in $pkg/PKGBUILD
    (otherwise pacman will not update installed systems), or use --force to replace it."
    fi
  done
  if [[ -e $pkgdir/.git ]] && command -v git >/dev/null &&
     [[ -n $(git -C "$pkgdir" status --porcelain) ]]; then
    warn "$pkg has uncommitted changes; they are built into the package."
  fi
fi

# --- build -------------------------------------------------------------------
# --syncdeps also installs the runtime depends on this machine; they stay
# installed, because the library check below needs them. A package
# without makedepends (calamares-wiamox: only config files) needs nothing
# to build, so its depends (calamares, grub, ...) are not installed here.
if (cd "$pkgdir" && makepkg --printsrcinfo) | grep -q '^[[:space:]]*makedepends = '; then
  deps=--syncdeps
else
  deps=--nodeps
fi

msg "Building $pkg in $BUILDDIR/$pkg (MAKEFLAGS=$MAKEFLAGS) ..."
(cd "$pkgdir" && makepkg --cleanbuild "$deps" --force --log)

mapfile -t files < <(cd "$pkgdir" && makepkg --packagelist)
built=()
for f in "${files[@]}"; do
  [[ -f $f ]] && built+=("$f")
done
(( ${#built[@]} )) || die "makepkg finished, but no package files were found."
msg "Built:"
printf '    %s\n' "${built[@]}"

# --- shared-library check ----------------------------------------------------
if (( libcheck )); then
  msg "Checking that every program and library in the package finds its libraries ..."
  check_libs "${built[@]}" ||
    die "The package needs libraries that are missing on this machine (see above).
    Nothing was added to woxKitchen. A path under /home means something from
    your home folder got into the build. --no-libcheck skips this check."
fi

# --- add to woxKitchen -------------------------------------------------------
if (( kitchen )); then
  db=$(kitchen_db)
  [[ -n $db ]] || db="$WIAMOX_KITCHEN/$WIAMOX_KITCHEN_DB.db.tar.zst"

  msg "Adding to woxKitchen ($db) ..."
  kitchen_files=()
  for f in "${built[@]}"; do
    cp -f -- "$f" "$WIAMOX_KITCHEN/"
    kitchen_files+=("$WIAMOX_KITCHEN/$(basename "$f")")
  done
  # -R deletes the package files of the versions being replaced.
  repo-add -R "$db" "${kitchen_files[@]}"
fi

# --- install -----------------------------------------------------------------
if (( install )); then
  msg "Installing on this machine ..."
  sudo pacman -U "${built[@]}"
fi

msg "Done."
if (( kitchen )); then
  echo "    The next woxclean1 ISO build takes $pkg from woxKitchen."
  echo "    To test on this machine first: sudo pacman -U ${built[*]}"
fi
