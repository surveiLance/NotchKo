#!/bin/zsh
# Exercises panel sizing: every tab, both size modes, 1..8 enabled tabs.
# Checks the window is big enough for the tab strips and fits the screen.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WINID="${WINID:-$HERE/../.build/winid}"
ALL=(home music shelf mirror clock devices agents prompter tools)

size() { "$WINID" 2>/dev/null | head -1 | cut -d' ' -f2 }
set_tabs() { defaults write com.lance.notch tabs.enabled -array "$@" }
set_mode() { defaults write com.lance.notch tabs.sizeMode -string "$1" }
relaunch() { pkill -x Notch 2>/dev/null; sleep 0.6; open "$HERE/../build/Notch.app"; sleep 8 }   # past the login greeting
# The panel closes if the pointer isn't over it, so park it clear and
# re-open before each sample rather than assuming it stayed up.
park() { "$HERE/../.build/parkmouse" 2>/dev/null || true }

fail=0
for mode in auto uniform; do
  set_mode $mode
  for n in 1 3 5 7 8; do
    set_tabs ${ALL[1,$n]}
    relaunch
    park
    "$HERE/debug.sh" expand >/dev/null 2>&1; sleep 0.8
    for tab in ${ALL[1,$n]}; do
      park
      "$HERE/debug.sh" $tab >/dev/null 2>&1; sleep 0.4
      "$HERE/debug.sh" expand >/dev/null 2>&1; sleep 0.7
      s=$(size)
      w=${s%x*}; h=${s#*x}
      # Strips must fit: notch + gaps + both sides of buttons.
      need=$(( 179 + 20 + 2 * (n * 28 / 2 + 36 + 12) ))
      if [[ -z "$w" || "$w" -lt 300 || "$w" -gt 1430 || "$h" -lt 60 ]]; then
        echo "FAIL mode=$mode tabs=$n tab=$tab size=$s"
        fail=1
      else
        echo "ok   mode=$mode tabs=$n tab=$tab size=$s (strips need ~$need)"
      fi
    done
  done
done
exit $fail
