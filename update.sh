#!/usr/bin/env bash
# Bump the PKGBUILD to a Claude Desktop release published in Anthropic's apt
# repository, taking the .deb checksums from the repository's own index rather
# than from a local download.
#
# The index is trusted only after its signature is checked: InRelease is
# verified against the pinned Anthropic release key, the Packages files are
# verified against the SHA256 listed in InRelease, and the .deb checksums that
# land in the PKGBUILD come from there.
#
#   ./update.sh              bump to the newest version
#   ./update.sh 1.32352.1    pin a specific version
#   ./update.sh --no-verify  skip the OpenPGP check (HTTPS only)
#   ./update.sh --check      report only, change nothing
#
# --check exits 0 when there is nothing to do, 10 when upstream has published
# a version newer than the PKGBUILD, and 11 when the PKGBUILD is current but
# the installed package is behind it. Any other non-zero exit is an error.

set -euo pipefail

readonly BASE='https://downloads.claude.ai/claude-desktop'
readonly APT="${BASE}/apt/stable"
readonly KEY_URL="${BASE}/key.asc"
# https://code.claude.com/docs/en/desktop-linux
readonly KEY_FPR='31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE'

cd "$(dirname "$(readlink -f "$0")")"

verify=1
check=0
want=''
for arg in "$@"; do
  case "$arg" in
    --no-verify) verify=0 ;;
    --check) check=1 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) want="$arg" ;;
  esac
done

die() { echo "update.sh: $*" >&2; exit 1; }

# Progress, not output: it belongs on stderr, where it still reaches the
# terminal but stays out of what a caller captures. --check's one line of
# stdout ends up in a desktop notification, where a leading banner would push
# the versions off the end of it.
say() { echo "$*" >&2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() { curl -fsSL "$1" -o "$2" || die "download failed: $1"; }

# --- signed repository index -------------------------------------------------

fetch "${APT}/dists/stable/InRelease" "$tmp/InRelease"

if (( verify )); then
  command -v gpg >/dev/null || die "gpg not found (install gnupg, or pass --no-verify)"
  fetch "$KEY_URL" "$tmp/key.asc"

  got_fpr=$(gpg --show-keys --with-colons "$tmp/key.asc" | awk -F: '$1=="fpr"{print $10; exit}')
  [[ $got_fpr == "$KEY_FPR" ]] \
    || die "signing key fingerprint mismatch: got ${got_fpr:-none}, expected $KEY_FPR"

  gpg --dearmor < "$tmp/key.asc" > "$tmp/keyring.gpg"
  gpgv --keyring "$tmp/keyring.gpg" "$tmp/InRelease" 2>/dev/null \
    || die "InRelease signature verification failed"
  say "==> InRelease signature OK (${KEY_FPR})"
else
  say "==> skipping signature verification (--no-verify)"
fi

# SHA256 the InRelease claims for a file listed under its SHA256: section.
index_sha() {
  awk -v want="$1" '
    /^SHA256:/ { in_sha = 1; next }
    /^[^ ]/    { in_sha = 0 }
    in_sha && $3 == want { print $1; exit }
  ' "$tmp/InRelease"
}

# --- newest version, and its .deb checksum, per architecture -----------------

declare -A sha_of
version=''

for debarch in amd64 arm64; do
  rel="main/binary-${debarch}/Packages"
  fetch "${APT}/dists/stable/${rel}" "$tmp/Packages.$debarch"

  if (( verify )); then
    expected=$(index_sha "$rel")
    [[ -n $expected ]] || die "InRelease does not list $rel"
    actual=$(sha256sum "$tmp/Packages.$debarch" | cut -d' ' -f1)
    [[ $actual == "$expected" ]] || die "$rel checksum mismatch"
  fi

  # One "version sha256 filename" line per stanza, oldest first.
  awk -v RS='' '
    {
      ver = sha = fn = ""
      n = split($0, line, "\n")
      for (i = 1; i <= n; i++) {
        if (line[i] ~ /^Version: /)  ver = substr(line[i], 10)
        if (line[i] ~ /^SHA256: /)   sha = substr(line[i], 9)
        if (line[i] ~ /^Filename: /) fn  = substr(line[i], 11)
      }
      if (ver != "" && sha != "" && fn != "") print ver, sha, fn
    }
  ' "$tmp/Packages.$debarch" | sort -V > "$tmp/list.$debarch"

  [[ -s $tmp/list.$debarch ]] || die "no packages found for $debarch"

  if [[ -n $want ]]; then
    row=$(awk -v v="$want" '$1 == v' "$tmp/list.$debarch")
    [[ -n $row ]] || die "version $want is not published for $debarch"
  else
    row=$(tail -n1 "$tmp/list.$debarch")
  fi

  read -r ver sha fn <<<"$row"

  # The PKGBUILD builds this URL itself; make sure upstream has not moved the pool.
  [[ $fn == "pool/main/c/claude-desktop/claude-desktop_${ver}_${debarch}.deb" ]] \
    || die "unexpected pool path for $debarch: $fn"

  if [[ -z $version ]]; then
    version=$ver
  elif [[ $version != "$ver" ]]; then
    die "newest version differs per architecture ($version vs $ver); pass one explicitly"
  fi

  sha_of[$debarch]=$sha
done

current=$(awk -F= '$1 == "pkgver" { print $2; exit }' PKGBUILD)

# --- check mode: report, touch nothing ---------------------------------------

if (( check )); then
  # pacman -Q needs no database lock, so this is safe to run while pacman holds
  # one -- which is exactly when check-update.sh calls it.
  installed=$(pacman -Q claude-desktop-bin 2>/dev/null | awk '{print $2}')
  echo "published ${version} | PKGBUILD ${current} | installed ${installed:-none}"

  if [[ $current != "$version" ]]; then
    echo "a newer release has been published"
    exit 10
  fi
  if [[ ${installed%-*} != "$version" ]]; then
    echo "the PKGBUILD is current but the installed package is not"
    exit 11
  fi
  echo "up to date"
  exit 0
fi

# --- rewrite the PKGBUILD ----------------------------------------------------


if [[ $current == "$version" ]]; then
  say "==> already at $version; refreshing checksums and .SRCINFO"
else
  say "==> ${current} -> ${version}"
fi

sed -i \
  -e "s|^pkgver=.*|pkgver=${version}|" \
  -e "s|^sha256sums_x86_64=.*|sha256sums_x86_64=('${sha_of[amd64]}')|" \
  -e "s|^sha256sums_aarch64=.*|sha256sums_aarch64=('${sha_of[arm64]}')|" \
  PKGBUILD

# A new upstream version always starts back at pkgrel=1; a checksum-only
# refresh leaves the packaging revision alone.
[[ $current == "$version" ]] || sed -i 's|^pkgrel=.*|pkgrel=1|' PKGBUILD

makepkg --printsrcinfo > .SRCINFO

say "==> PKGBUILD and .SRCINFO updated to ${version}"
