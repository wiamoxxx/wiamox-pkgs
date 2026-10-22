#!/usr/bin/env bash
# Installs the custom nodes listed in nodes.txt into $NODE_DIR and their
# Python dependencies into the package's own Python ($PY). Build time only.
#
#   PY            interpreter of the package environment
#   NODES_FILE    nodes.txt
#   NODE_DIR      target folder for the node checkouts
#   CONSTRAINTS   file with versions that must not change (torch, numpy, ...)
#   REPORT        written: one "ok|FAILED <node> <what>" line per problem
#
# A failing node does not stop the build (the others are still useful); the
# report says what failed and the smoke test in check() shows whether the
# node still loads.
set -uo pipefail
: "${PY:?}" "${NODES_FILE:?}" "${NODE_DIR:?}" "${CONSTRAINTS:?}" "${REPORT:?}"
TORCH_BACKEND=${TORCH_BACKEND:-cu130}
mkdir -p "$NODE_DIR"
: > "$REPORT"

pipi() {
  uv pip install --python "$PY" --no-cache --compile-bytecode \
    --torch-backend "$TORCH_BACKEND" -c "$CONSTRAINTS" "$@"
}
bad=0
fail() { bad=1; echo "FAILED $1 $2" | tee -a "$REPORT"; }

while read -r repo directory ref _; do
  [[ -z ${repo:-} || $repo == \#* ]] && continue
  echo "=== $directory ($repo ${ref:-HEAD}) ==="
  bad=0
  cd "$NODE_DIR" || exit 1

  if [[ ! -d $directory ]]; then
    if [[ -n ${ref:-} ]]; then
      # fetch works for a tag, a branch and a full commit hash
      git init -q "$directory" &&
        git -C "$directory" remote add origin "$repo" &&
        git -C "$directory" fetch -q --depth 1 origin "$ref" &&
        git -C "$directory" checkout -q FETCH_HEAD || { fail "$directory" "checkout"; continue; }
    else
      git clone -q --depth 1 "$repo" "$directory" || { fail "$directory" "clone"; continue; }
    fi
  fi
  cd "$directory" || continue

  # e.g. UltimateSDUpscale keeps its core script in a submodule; without it
  # the node downloads it at import time, which cannot work offline.
  if [[ -f .gitmodules ]]; then
    git submodule update --init --recursive --depth 1 || fail "$directory" "submodules"
  fi

  if [[ -f requirements.txt ]]; then
    pipi -r requirements.txt || fail "$directory" "requirements.txt"
  elif [[ -f pyproject.toml ]]; then
    # Only the declared dependencies: ComfyUI loads the folder itself, and
    # building flat-layout nodes as packages fails.
    "$PY" - <<'PYEOF' > .wiamox-deps.txt
import tomllib
with open("pyproject.toml", "rb") as fh:
    print("\n".join(tomllib.load(fh).get("project", {}).get("dependencies", [])))
PYEOF
    if grep -q '[^[:space:]]' .wiamox-deps.txt; then
      pipi -r .wiamox-deps.txt || fail "$directory" "pyproject dependencies"
    fi
    rm -f .wiamox-deps.txt
  fi

  # ComfyUI-Manager convention: some nodes finish their setup in install.py.
  if [[ -f install.py ]]; then
    "$PY" install.py || fail "$directory" "install.py"
  fi
  (( bad )) || echo "ok $directory" >> "$REPORT"
done < "$NODES_FILE"

echo "--- node report ---"; cat "$REPORT"
exit 0
