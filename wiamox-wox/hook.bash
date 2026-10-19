# WiamOX "wox why" hook (bash). Sourced from ~/.bashrc, BEFORE starship.
# Same behaviour as hook.zsh: failed commands only, no output stored, tiny
# tmpfs file removed at exit, max 8 entries, entries older than 1 h dropped.
[[ $- == *i* ]] || return 0

export WOX_SESSION=$$
_wox_dir="${XDG_RUNTIME_DIR:-/tmp/wox-$UID}/wox"
mkdir -p -m 700 "$_wox_dir" 2>/dev/null || return 0
_wox_seq=0
_wox_last_hist=-1

for _wox_f in "$_wox_dir"/*.seq; do
  [[ -e $_wox_f ]] || continue
  _wox_p=${_wox_f##*/}; _wox_p=${_wox_p%.seq}
  kill -0 "$_wox_p" 2>/dev/null || rm -f -- "${_wox_f%.seq}.seq" "${_wox_f%.seq}.log"
done
unset _wox_f _wox_p

_wox_precmd() {
  local rc=$?
  if [[ $_wox_last_hist -lt 0 ]]; then
    _wox_last_hist=$HISTCMD          # first prompt: nothing ran yet
    return $rc
  fi
  if [[ $HISTCMD != "$_wox_last_hist" ]]; then
    _wox_last_hist=$HISTCMD
    local c
    c=$(HISTTIMEFORMAT= builtin history 1)
    c=${c#"${c%%[![:space:]]*}"}; c=${c#*[[:space:]]}
    c=${c#"${c%%[![:space:]]*}"}
    c=${c//$'\t'/ }; c=${c//$'\n'/ }; c=${c:0:500}
    case $c in
      "wox "*|wox|why|why\ *) return $rc ;;
    esac
    _wox_seq=$((_wox_seq + 1))
    printf '%s\n' "$_wox_seq" >"$_wox_dir/$$.seq"
    if (( rc != 0 && rc != 130 && rc != 141 )); then
      local f="$_wox_dir/$$.log" now tmp
      printf -v now '%(%s)T' -1
      printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$rc" "$_wox_seq" "$PWD" "$c" >>"$f"
      tmp=$(tail -n 8 -- "$f" | awk -F'\t' -v now="$now" 'now - $1 < 3600')
      printf '%s\n' "$tmp" >"$f"
    fi
  fi
  return $rc
}

case ";${PROMPT_COMMAND:-};" in
  *";_wox_precmd;"*) ;;
  *) PROMPT_COMMAND="_wox_precmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
[[ -z $(trap -p EXIT) ]] && trap 'rm -f -- "$_wox_dir/$$.seq" "$_wox_dir/$$.log"' EXIT
command -v why >/dev/null 2>&1 || alias why='wox why'
