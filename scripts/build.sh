#!/usr/bin/env bash
# Builds one package of this repo with makepkg and adds it to your local
# woxKitchen repo, ready for the ISO build (woxclean1) to pick up.
#
#   scripts/build.sh linux                build the kernel, add it to woxKitchen
#   scripts/build.sh linux --install      ... and install it on this machine too
#   scripts/build.sh linux --no-kitchen   only build, leave woxKitchen alone
#   scripts/build.sh linux --force        rebuild a version woxKitchen already has
#   scripts/build.sh calamares-wiamox     the installer config (git submodule)
#   scripts/build.sh woxed                the WiamOX Editor (git submodule)
#   scripts/build.sh calamares            the installer program, from the AUR
#   scripts/build.sh coreutils            Arch's coreutils + patches in coreutils/
#   scripts/build.sh <pkg> --no-libcheck  skip the shared-library check
#
# Packages go to out/, logs to build/logs/. Settings come from local.conf
# in the repo root (copy local.conf.example); WIAMOX_* variables set in the
# environment win over it.
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# --- arguments ---------------------------------------------------------------
pkg=""
install=0
kitchen=1
force=0
libcheck=1
for arg in "$@"; do
  case $arg in
    --install) install=1 ;;
    --no-kitchen) kitchen=0 ;;
    --force) force=1 ;;
    --no-libcheck) libcheck=0 ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $arg" >&2; usage 1 ;;
    *) [[ -z $pkg ]] || usage 1; pkg=${arg%/} ;;
  esac
done
[[ -n $pkg ]] || usage 1
[[ $EUID -ne 0 ]] || die "Run this as your normal user; makepkg refuses to run as root."
command -v makepkg >/dev/null || die "makepkg not found (this needs an Arch-based system)."

# Packages built straight from the AUR. Their recipes are not part of this
# repo: they are cloned into aur/<name> and updated on every build.
aur_packages=(calamares)
# Arch packages with WiamOX changes: Arch's current recipe is cloned into
# arch/<name> on every build, and <name>/patches/*.patch from this repo are
# applied on top (see make_wiamox_recipe in common.sh).
arch_packages=(coreutils)
is_aur=0 is_arch=0
for name in "${aur_packages[@]}"; do
  [[ $pkg != "$name" ]] || is_aur=1
done
for name in "${arch_packages[@]}"; do
  [[ $pkg != "$name" ]] || is_arch=1
done

if (( is_aur )); then
  pkgdir="$ROOT/aur/$pkg"
  recipe_update "$pkgdir" "$pkg" "https://aur.archlinux.org/$pkg.git" "the AUR" ask
elif (( is_arch )); then
  recipe_update "$ROOT/arch/$pkg" "$pkg" \
    "https://gitlab.archlinux.org/archlinux/packaging/packages/$pkg.git" "Arch"
  pkgdir="$ROOT/arch/$pkg.wiamox"
  make_wiamox_recipe "$ROOT/arch/$pkg" "$ROOT/$pkg" "$pkgdir"
  # Arch keeps the signing keys of the source tarballs next to the recipe;
  # makepkg needs them to verify the download.
  if compgen -G "$ROOT/arch/$pkg/keys/pgp/*.asc" >/dev/null; then
    gpg --quiet --import "$ROOT/arch/$pkg"/keys/pgp/*.asc 2>/dev/null ||
      warn "Could not import the PGP keys in arch/$pkg/keys/pgp/."
  fi
else
  pkgdir="$ROOT/$pkg"
  # Submodules (calamares-wiamox, woxed) are empty after a plain git clone.
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
export BUILDDIR=${WIAMOX_BUILDDIR:-$ROOT/build}
# Kept out of the package folders, so the submodules stay clean. SRCDEST
# holds downloaded sources (woxed: Neovim, ~33 plugin repos) between builds.
export PKGDEST=$ROOT/out LOGDEST=$BUILDDIR/logs SRCDEST=${SRCDEST:-$BUILDDIR/sources}
mkdir -p "$PKGDEST" "$LOGDEST" "$SRCDEST"
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
      if (( is_arch )); then
        die "woxKitchen already has $name. After changing $pkg/patches/ without a new Arch
    version, raise WIAMOX_PKGREL in $pkg/wiamox.conf (otherwise pacman will not
    update installed systems), or use --force to replace it."
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
