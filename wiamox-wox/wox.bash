# bash completion for wox (WiamOX terminal helper).

_wox() {
  local cur=${COMP_WORDS[COMP_CWORD]} words
  if (( COMP_CWORD == 1 )); then
    words="install remove update search info list clean why help"
  else
    case ${COMP_WORDS[1]} in
      install|i) words=$(pacman -Slq 2>/dev/null) ;;
      remove|rm) words=$(pacman -Qq 2>/dev/null) ;;
      info)      words=$(pacman -Slq 2>/dev/null; pacman -Qq 2>/dev/null) ;;
      why|diagnose) words="-p --paste" ;;
      *) return 0 ;;
    esac
  fi
  mapfile -t COMPREPLY < <(compgen -W "$words" -- "$cur")
}
complete -F _wox wox
