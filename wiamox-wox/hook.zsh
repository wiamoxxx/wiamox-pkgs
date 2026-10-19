# WiamOX "wox why" hook (zsh). Sourced from ~/.zshrc, BEFORE starship.
#
# Records only the *failed* commands of this terminal (command, exit code,
# directory, time) in a tiny file under $XDG_RUNTIME_DIR (tmpfs). It never
# stores command output. Cleanup: the file is removed when the shell exits,
# files of dead shells are swept on start, at most 8 entries are kept and
# entries older than one hour are dropped.
[[ -o interactive ]] || return 0
zmodload zsh/datetime 2>/dev/null

export WOX_SESSION=$$
_wox_dir="${XDG_RUNTIME_DIR:-/tmp/wox-$UID}/wox"
mkdir -p -m 700 "$_wox_dir" 2>/dev/null || return 0
_wox_seq=0
_wox_cmd=

# sweep files of shells that no longer exist
for _wox_f in "$_wox_dir"/*.seq(N); do
  kill -0 "${_wox_f:t:r}" 2>/dev/null || rm -f -- "${_wox_f:r}".seq "${_wox_f:r}".log
done
unset _wox_f

_wox_preexec() { _wox_cmd=$1 }

_wox_precmd() {
  local rc=$?
  if [[ -n $_wox_cmd ]]; then
    local c=${_wox_cmd//$'\t'/ }
    c=${c//$'\n'/ }
    c=${c:0:500}
    _wox_cmd=
    case $c in
      "wox "*|wox|why|why\ *) return $rc ;;
    esac
    (( _wox_seq++ ))
    print -r -- $_wox_seq >| "$_wox_dir/$$.seq"
    if (( rc != 0 && rc != 130 && rc != 141 )); then
      local f="$_wox_dir/$$.log" now=$EPOCHSECONDS tmp
      print -r -- "$now"$'\t'"$rc"$'\t'"$_wox_seq"$'\t'"$PWD"$'\t'"$c" >> "$f"
      tmp=$(tail -n 8 -- "$f" | awk -F'\t' -v now="$now" 'now - $1 < 3600')
      print -r -- "$tmp" >| "$f"
    fi
  fi
  return $rc
}

_wox_zshexit() { rm -f -- "$_wox_dir/$$.seq" "$_wox_dir/$$.log" }

autoload -Uz add-zsh-hook
add-zsh-hook preexec _wox_preexec
add-zsh-hook precmd _wox_precmd
add-zsh-hook zshexit _wox_zshexit
command -v why >/dev/null 2>&1 || alias why='wox why'
