#!/usr/bin/env bash
# Build and install claude-desktop-bin, then offer the optional feature groups.
#
# pacman cannot ask this from inside the package: an .install script runs
# within the transaction that holds the database lock, so it cannot install
# anything, and interactive prompts there break --noconfirm and unattended
# upgrades. Hence a wrapper around the install instead of a hook inside it.
#
#   ./install.sh              build if needed, install, ask about extras
#   ./install.sh -y           accept every optional group
#   ./install.sh -n           install the package only
#   ./install.sh --dry-run    print what would run, change nothing

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

(( EUID != 0 )) || { echo "install.sh: run as a normal user, not root" >&2; exit 1; }

answer=ask
dry=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes)         answer=yes ;;
    -n|--no-optional) answer=no ;;
    --dry-run)        dry=1 ;;
    -h|--help)        sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

run() {
  if (( dry )); then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

installed() { pacman -Qq "$1" >/dev/null 2>&1; }

# Ask about one optional group. Skips silently when everything is present.
offer() {
  local title=$1 why=$2; shift 2
  local missing=()
  for p in "$@"; do installed "$p" || missing+=("$p"); done

  if (( ${#missing[@]} == 0 )); then
    printf '  %s: already installed\n' "$title"
    return
  fi

  local reply
  case $answer in
    yes) reply=y ;;
    no)  reply=n ;;
    *)
      printf '\n%s\n  %s\n  installs: %s\n' "$title" "$why" "${missing[*]}"
      # Default to no when stdin is not a terminal, so piping stays safe.
      if [[ -t 0 ]]; then
        read -rp '  install these? [y/N] ' reply || reply=n
      else
        reply=n
      fi
      ;;
  esac

  if [[ ${reply,,} == y* ]]; then
    # --asdeps keeps them out of the explicit list; pacman -Qdt will not call
    # them orphans, because optdepends count as "optionally required".
    run sudo pacman -S --needed --asdeps "${missing[@]}"
  fi
}

# --- the package itself ------------------------------------------------------

carch=$(uname -m)
# Ask makepkg where the package goes rather than assuming the checkout and
# .pkg.tar.zst: PKGDEST and PKGEXT in makepkg.conf can move or rename it.
# options=(!debug) means this is the one package the PKGBUILD builds.
pkgfile=$(makepkg --packagelist | head -n1)
[[ -n $pkgfile ]] || { echo "install.sh: makepkg --packagelist printed nothing" >&2; exit 1; }

if [[ ! -f $pkgfile ]]; then
  echo "==> building ${pkgfile##*/}"
  run makepkg -f
else
  echo "==> using existing ${pkgfile##*/}"
fi

echo "==> installing"
run sudo pacman -U --needed "$pkgfile"

# --- optional feature groups -------------------------------------------------

echo
echo "==> optional features"

case $carch in
  aarch64) vm_pkgs=(qemu-system-aarch64 edk2-aarch64 virtiofsd) ;;
  *)       vm_pkgs=(qemu-system-x86 edk2-ovmf virtiofsd) ;;
esac

offer "Cowork sandbox VM" \
      "runs Cowork's sandbox in a QEMU virtual machine" \
      "${vm_pkgs[@]}"

offer "Claude Code sandboxed Bash" \
      "filesystem isolation and network proxy for the Bash tool" \
      bubblewrap socat

# The tray itself is StatusNotifierItem over D-Bus, implemented in Electron
# itself -- no appindicator library involved. Only the menu is dlopen'd.
offer "Tray icon menu" \
      "context menu for the StatusNotifierItem tray icon" \
      libdbusmenu-glib

# No group for the GNOME search provider: it needs gjs, and gnome-shell
# already depends on gjs, so anyone who can use the provider has it. Offering
# it could only install gjs on desktops where the provider does nothing.

echo
echo "==> done. launch with: claude-desktop"
echo "    remaining optional deps (desktop-specific) are listed by:"
echo "      pacman -Qi claude-desktop-bin"
echo "    extra command-line switches go in:"
echo "      ~/.config/claude-desktop-flags.conf   (see /etc/claude-desktop-flags.conf)"
