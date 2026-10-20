#!/bin/bash
# Launcher for the Claude desktop app.
#
# Upstream's /usr/bin/claude-desktop is a bare symlink to the Electron binary,
# which leaves no place to put a command-line switch that survives an upgrade:
# the desktop entry is a package file, so edits to its Exec= line are lost on
# every rebuild. This wrapper reads switches from a flags file instead and is
# otherwise a plain exec -- with no flags file it behaves exactly like the
# symlink it replaces.
#
# Read in order, both optional:
#   /etc/claude-desktop-flags.conf
#   ${XDG_CONFIG_HOME:-~/.config}/claude-desktop-flags.conf
#
# One or more switches per line, '#' starts a comment, CR is stripped so a
# file with CRLF endings does not produce switches ending in \r. Lines are
# split on whitespace and quoting is not interpreted, so a switch's value
# cannot contain spaces. Switches from the files come before the ones on the
# command line, so a switch given on the command line wins wherever Chromium
# takes the last occurrence.
#
# Nothing here may stop the app from starting: a path that is not a readable
# regular file is skipped rather than treated as an error, which also keeps a
# directory or a fifo at either location from aborting or hanging the launch.
#
# Only switches belong here. Environment variables do not: export those from
# ~/.config/environment.d/ instead, which also covers Electron's own
# ELECTRON_OZONE_PLATFORM_HINT.

set -euo pipefail

_read_flags() {
  local file=$1 line words
  [[ -f $file && -r $file ]] || return 0
  while IFS= read -r line || [[ -n ${line:-} ]]; do
    line=${line%%#*}
    line=${line//$'\r'/}
    [[ -n ${line//[[:space:]]/} ]] || continue
    read -r -a words <<<"$line"
    flags+=("${words[@]}")
  done <"$file"
}

flags=()
_read_flags /etc/claude-desktop-flags.conf
_read_flags "${XDG_CONFIG_HOME:-${HOME:-}/.config}/claude-desktop-flags.conf"

exec /usr/lib/claude-desktop/claude-desktop "${flags[@]}" "$@"
