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
