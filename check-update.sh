#!/bin/bash
# Ask update.sh whether a newer Claude Desktop has been published, and raise a
# desktop notification if so. Meant to be fired by
# claude-desktop-update-check.path, which triggers on pacman taking its
# database lock -- so this runs beside `pacman -Syu` / `yay -Syu` rather than
# inside it, and cannot slow either of them down.
#
# Nothing here writes to the pacman database, and `pacman -Q` needs no lock,
# so running while pacman still holds one is safe.
#
#   ./check-update.sh          check, subject to the rate limit
#   ./check-update.sh --force  check now, ignoring the rate limit

# No -e: a failed check must still record its result and clear the way for the
# next one.
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")"

cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-desktop-update"
stamp="$cache/last-check"
status="$cache/status"
mkdir -p "$cache"

# The doorbell is pacman's lock, which every writing operation takes -- so
# `-U`, `-S pkg` and `-R` ring it too, and checking for a Claude release right
# after installing an unrelated package is just noise. pacman logs its own
# command line, so narrow it here to a system upgrade, the one moment the
# answer is wanted. Nothing pacman exposes to a hook could do this: triggers
# match transactions, not the flags that caused them.
#
# Counts as an upgrade: a sync with `u` (`-Syu`, `--sync --sysupgrade`), or a
# sync that only refreshes, with `y` and no package names. The second is how
# yay runs `yay -Syu`: it logs a refresh, `pacman -S -y --config
# /etc/pacman.conf --`, and a separate `-S -y -u` only when repo packages need
# upgrading, so with AUR-only updates or none the refresh is all there is. It
# lets a bare `pacman -Sy` through too, which costs one check.
#
# Fails open only where nothing can be read: an unreadable log or no Running
# line means the check runs. A line that is read is judged by its flags.
_is_sysupgrade() {
  local tok toks sync=0 upgrade=0 refresh=0 targets=0 skip=0 ended=0
  read -ra toks <<<"$1"
  for tok in "${toks[@]:1}"; do  # [0] is the program name
    if (( skip )); then skip=0; continue; fi
    if (( ended )); then targets=1; continue; fi
    case $tok in
      --)           ended=1 ;;
      --sysupgrade) upgrade=1 ;;
      --sync)       sync=1 ;;
      --refresh)    refresh=1 ;;
      # Long options whose value is the next word, not a package name.
      --config|--dbpath|--root|--sysroot|--cachedir|--logfile|--gpgdir|\
      --hookdir|--arch|--ignore|--ignoregroup|--assume-installed|\
      --overwrite|--print-format|--color)
                    skip=1 ;;
      --*)          ;;  # any other long option, and never a short cluster
      -*)           [[ $tok == *S* ]] && sync=1
                    [[ $tok == *u* ]] && upgrade=1
                    [[ $tok == *y* ]] && refresh=1 ;;
      *)            targets=1 ;;
    esac
  done
  (( sync && (upgrade || (refresh && !targets)) ))
}

if [[ ${1:-} != --force ]]; then
  # The line pacman writes as it starts, so during the run it is the last one.
  # PACMAN_LOG is an override for the tests; nothing else sets it.
  invocation=$(grep -a "\[PACMAN\] Running '" "${PACMAN_LOG:-/var/log/pacman.log}" 2>/dev/null |
                 tail -1 | sed "s/.*Running '//; s/'\$//")
  if [[ -n $invocation ]] && ! _is_sysupgrade "$invocation"; then
    exit 0
  fi
fi

# One pacman run can take and drop the lock several times, and an upgrade is
# often followed straight away by another command. Without a floor, each would
# cost a round trip to the index.
interval=${CLAUDE_UPDATE_MIN_INTERVAL:-600}
if [[ ${1:-} != --force && -f $stamp ]]; then
  now=$(date +%s)
  last=$(date -r "$stamp" +%s 2>/dev/null || echo 0)
  if (( now - last < interval )); then
    exit 0
  fi
fi

# stdout and stderr are kept apart on purpose: update.sh puts its progress on
# stderr, and only stdout -- the versions and the verdict -- belongs in a
# notification, which shows the first line or two and truncates the rest.
# The status file gets both.
err=$(mktemp)
out=$(./update.sh --check 2>"$err")
rc=$?

# Before the notification, so a hung or failing check cannot repeat on every
# pacman invocation.
touch "$stamp"
{ date -Is; printf 'exit %s\n' "$rc"; printf '%s\n' "$out"; cat "$err"; } > "$status"
rm -f "$err"

case $rc in
  10) title='Claude Desktop: a new release is out'
      body="${out}"$'\n\n'"cd ${PWD} && ./update.sh && ./install.sh" ;;
  11) title='Claude Desktop: built but not installed'
      body="${out}"$'\n\n'"cd ${PWD} && ./install.sh" ;;
  12) title='Claude Desktop: upstream withdrew a release'
      body="${out}"$'\n\n'"To follow it back: cd ${PWD} && ./update.sh <version> && ./install.sh" ;;
  0)  exit 0 ;;
  # Errors stay quiet: the usual cause is the network being down, which the
  # pacman run that triggered this will have complained about already. The
  # reason is in $status either way.
  *)  exit 0 ;;
esac

notify-send --app-name='Claude Desktop' --icon=claude-desktop \
  --urgency=normal --expire-time=0 -- "$title" "$body"
