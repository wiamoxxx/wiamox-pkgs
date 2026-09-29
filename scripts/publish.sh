#!/usr/bin/env bash
# Publishes woxKitchen online, so any machine can use its packages: a
# GitHub Release holds the package files and a pacman database, and pacman
# downloads straight from it.
#
#   scripts/publish.sh             upload what changed, remove what is gone
#   scripts/publish.sh --dry-run   only show what would change
#
# Publishes exactly the packages woxKitchen's database lists, under the
# repo name [woxkitchen]. In pacman.conf, above [core]:
#
#   [woxkitchen]
#   SigLevel = Optional TrustAll
#   Server = https://github.com/wiamoxxx/wiamox-pkgs/releases/download/x86_64
#
# Needs github-cli (pacman -S github-cli), logged in once with: gh auth login
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

dry_run=0
for arg in "$@"; do
  case $arg in
    --dry-run|-n) dry_run=1 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $arg" >&2; usage 1 ;;
  esac
done

load_conf
REPO=${WIAMOX_PUBLISH_REPO:-wiamoxxx/wiamox-pkgs}
TAG=${WIAMOX_PUBLISH_TAG:-x86_64}
NAME=${WIAMOX_PUBLISH_DB:-woxkitchen}
SERVER="https://github.com/$REPO/releases/download/$TAG"

# --- checks ------------------------------------------------------------------
for tool in gh repo-add bsdtar sha256sum curl; do
  command -v "$tool" >/dev/null || die "$tool not found."
done
[[ -n ${WIAMOX_KITCHEN-} ]] || die "WIAMOX_KITCHEN is not set (local.conf)."
db=$(kitchen_db)
[[ -n $db ]] || die "No $WIAMOX_KITCHEN_DB.db.tar.* in $WIAMOX_KITCHEN; build something first (scripts/build.sh)."
gh auth status >/dev/null 2>&1 || die "github-cli is not logged in. Run: gh auth login"

visibility=$(gh repo view "$REPO" --json visibility --jq .visibility) ||
  die "Cannot read $REPO on GitHub."
if [[ $visibility != PUBLIC ]]; then
  die "$REPO is ${visibility,,}. pacman cannot log in to GitHub, so it can only
    download release files from a public repository. Make it public
    (gh repo edit $REPO --visibility public --accept-visibility-change-consequences)
    or set WIAMOX_PUBLISH_REPO in local.conf to a public repository."
fi

# --- 1. what woxKitchen has ---------------------------------------------------
# Taken from its database, so leftover files in the folder are not published.
mapfile -t pkgs < <(bsdtar -xOf "$db" | awk '$0 == "%FILENAME%" { getline; print }' | sort)
(( ${#pkgs[@]} )) || die "woxKitchen's database lists no packages."

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# GitHub turns every character other than letters, digits, '.', '-' and '_'
# in a file name into '.' (the ':' of an epoch, a '+' in a version). The
# files are renamed that way before repo-add, so the database lists the
# names GitHub really serves. pacman does not care about the file name.
staged=()      # packages and signatures, as uploaded
staged_pkgs=() # packages only, for repo-add
for f in "${pkgs[@]}"; do
  [[ -f $WIAMOX_KITCHEN/$f ]] || die "woxKitchen's database lists $f, but the file is missing."
  safe=${f//[^A-Za-z0-9._-]/.}
  ln -f "$WIAMOX_KITCHEN/$f" "$stage/$safe" 2>/dev/null || cp -f "$WIAMOX_KITCHEN/$f" "$stage/$safe"
  staged+=("$safe")
  staged_pkgs+=("$safe")
  if [[ -f $WIAMOX_KITCHEN/$f.sig ]]; then
    cp -f "$WIAMOX_KITCHEN/$f.sig" "$stage/$safe.sig"
    staged+=("$safe.sig")
  fi
done

msg "Building the [$NAME] database for ${#pkgs[@]} package(s) ..."
(cd "$stage" && repo-add -q "$NAME.db.tar.gz" "${staged_pkgs[@]}")
# pacman downloads $NAME.db and $NAME.files; repo-add made those symlinks,
# and a release can only hold real files.
for x in db files; do
  rm -f "$stage/$NAME.$x"
  mv "$stage/$NAME.$x.tar.gz" "$stage/$NAME.$x"
done
# Checksums of what is online, so the next run only uploads what changed.
(cd "$stage" && sha256sum -- "${staged[@]}") > "$stage/$NAME.sha256"

# --- 2. what the release has --------------------------------------------------
remote_assets=()
mkdir -p "$stage/remote"
touch "$stage/remote/$NAME.sha256"
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  mapfile -t remote_assets < <(gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name')
  if printf '%s\n' "${remote_assets[@]}" | grep -qxF "$NAME.sha256"; then
    gh release download "$TAG" -R "$REPO" -p "$NAME.sha256" -D "$stage/remote" --clobber
  fi
  release_exists=1
else
  release_exists=0
fi

upload=()
for f in "${staged[@]}"; do
  sum=$(awk -v f="$f" '$2 == f { print $1 }' "$stage/$NAME.sha256")
  if ! printf '%s\n' "${remote_assets[@]}" | grep -qxF "$f" ||
     ! grep -qxF "$sum  $f" "$stage/remote/$NAME.sha256"; then
    upload+=("$f")
  fi
done

remove=()
for a in "${remote_assets[@]}"; do
  case $a in
    "$NAME.db"|"$NAME.files"|"$NAME.sha256") continue ;;
  esac
  printf '%s\n' "${staged[@]}" | grep -qxF "$a" || remove+=("$a")
done

msg "Publishing to $SERVER"
(( release_exists )) || echo "    new release '$TAG' in $REPO"
if (( ${#upload[@]} )); then
  printf '    upload  %s\n' "${upload[@]}"
else
  echo "    (all packages are already online)"
fi
if (( ${#remove[@]} )); then
  printf '    remove  %s\n' "${remove[@]}"
fi
echo "    update  $NAME.db $NAME.files"

if (( dry_run )); then
  msg "Dry run, nothing changed."
  exit 0
fi

# --- 3. upload -----------------------------------------------------------------
if (( !release_exists )); then
  gh release create "$TAG" -R "$REPO" --latest=false \
    --title "WiamOX packages ($TAG)" \
    --notes "pacman repository [$NAME], published by scripts/publish.sh. Do not edit by hand.

\`\`\`
[$NAME]
SigLevel = Optional TrustAll
Server = $SERVER
\`\`\`"
fi

# Packages first, then the database: the database never lists a file
# that is not online yet.
if (( ${#upload[@]} )); then
  (cd "$stage" && gh release upload "$TAG" -R "$REPO" --clobber "${upload[@]}")
fi
(cd "$stage" && gh release upload "$TAG" -R "$REPO" --clobber "$NAME.db" "$NAME.files" "$NAME.sha256")
for a in "${remove[@]}"; do
  gh release delete-asset "$TAG" "$a" -R "$REPO" --yes
done

# --- 4. check it the way pacman will see it -----------------------------------
msg "Checking the online repo ..."
curl -fsSL -o "$stage/check.db" "$SERVER/$NAME.db" || die "Cannot download $SERVER/$NAME.db"
mapfile -t online < <(bsdtar -xOf "$stage/check.db" | awk '$0 == "%FILENAME%" { getline; print }')
for f in "${online[@]}"; do
  curl -fsIL -o /dev/null "$SERVER/$f" || die "$SERVER/$f is not downloadable."
  echo "    ok  $f"
done

msg "Done. [$NAME] is online with ${#online[@]} package(s):"
echo "    Server = $SERVER"
