# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Arch Linux packaging (`claude-desktop-bin`) for Anthropic's official Claude Desktop
`.deb`. Nothing is compiled and nothing in the Electron bundle is patched: `prepare()`
pulls `data.tar.*` out of the `.deb`, `package()` unpacks it into `$pkgdir`, and the rest
of `package()` translates or drops the Debian-specific wrapping around it.

Git history starts on 2026-10-21, with everything before it squashed into the initial
commit. For anything older than that, the PKGBUILD comments and `README.md` are the only
record of why things are the way they are, which makes them unusually load-bearing — keep
them true when you change the code under them.

`.claude/aur-comment.md` is a draft message to another AUR maintainer, not guidance.

## Commands

```bash
makepkg -f                      # build (~5 min; the payload is ~600 MB unpacked)
./install.sh                    # build if needed, install, offer the optional feature groups
./install.sh -y                 # accept every optional group
./install.sh --dry-run          # print what it would run
sudo pacman -U claude-desktop-bin-<pkgver>-<pkgrel>-x86_64.pkg.tar.zst

./update.sh                     # bump to the newest published release
./update.sh 3.1623.0            # pin a version
./update.sh --check             # report only; exit 0 current, 10 new release, 11 not installed
./update.sh --no-verify         # skip the OpenPGP check

makepkg --printsrcinfo > .SRCINFO   # REQUIRED after any PKGBUILD edit
namcap PKGBUILD                     # expected: no output at all
namcap claude-desktop-bin-*.pkg.tar.zst
./check-update.sh --force       # run the update notifier, ignoring its rate limit
```

There is no test suite. "Running the tests" here means: build, diff the package's file list
against the previous build, run `namcap`, and exercise `claude-desktop.sh` against a stub.

## The central invariant

Everything `package()` does beyond unpacking is derived from strings inside
`resources/app.asar` and files under `resources/` — upstream internals that can move in any
release without notice. When they move, the package still builds and the feature silently
stops working.

So `package()` **asserts them**. It greps `app.asar` for every hardcoded Debian path the
Cowork symlinks target, and checks the GNOME search provider's `.service` `Exec=` line
still names `/usr/bin/gjs` and a script inside this package's prefix. A bump that changes
one fails the build with a message naming it.

Keep this property when adding anything: **if a change depends on an upstream fact, assert
that fact in `package()`.** `makepkg` runs `package()` under `errexit` with an `ERR` trap,
so a bare `return 1` aborts the build.

Prefer an exact match over a loose one. The OVMF guard matches the
`replace("OVMF_CODE","OVMF_VARS")` call rather than the bare `OVMF_VARS` name, because the
drift it exists to catch — upstream swapping the derivation for explicit paths — would
still contain the bare name.

## What `package()` reproduces, and what it drops

Upstream's `postinst` (extract with `bsdtar -xf <deb> 'control.tar.*'`; it is heavily
commented and is the spec) registers five things at configure time:

| Upstream | Here |
| --- | --- |
| apt repo, keyring, unattended-upgrades snippet | **dropped** — updates come from this repo |
| `/etc/apparmor.d/claude-desktop` | packaged file, loaded by `claude-desktop-bin.install` |
| GNOME Shell search provider | packaged files in `/usr/share/{gnome-shell/search-providers,dbus-1/services}` |
| `/usr/share/mime/packages/com.anthropic.Claude.xml` | packaged file |
| `/usr/bin/ccd` symlink | created only when the build ships `resources/bin/ccd` |

The three copied registrations read from inside `$pkgdir`, and the originals stay in place
under `resources/` because the copies reference them there.

The Cowork shims exist because the app resolves its VM tooling through paths hardcoded for
Debian with no override: `/usr/share/OVMF/OVMF_CODE{_4M,}.fd`, `/usr/share/AAVMF/AAVMF_CODE.fd`,
`/usr/libexec/virtiofsd`, `/usr/bin/virtiofsd`. See the README for how each maps to Arch.

## Dependency policy

`depends` is grounded in evidence, and the comment above it records which kind for each
entry: `NEEDED` entries, dlopen soname strings, or upstream's Debian `Depends` alone.

- `libdrm`, `libxtst`, `util-linux-libs` have **no** `NEEDED` entry and no soname string
  anywhere in the payload. They are kept on upstream's authority. **Do not prune them from
  ELF analysis** — `namcap` will keep suggesting it.
- `libpipewire` is a hard `NEEDED` of
  `resources/app.asar.unpacked/node_modules/@ant/claude-native/claude-native-binding.node`.
- The Cowork VM stack stays in `optdepends`, mapping Debian's `Recommends`. The EDK2
  firmware is declared per architecture: `edk2-ovmf` is `arch=any` but ships no AAVMF, so
  aarch64 needs `edk2-aarch64`. `install.sh` must offer the same package per arch that
  `optdepends` declares, or its `--asdeps` reasoning stops holding.

Expected `namcap` output on the package is 33 warnings and **3 errors**. The errors are the
three Cowork symlinks pointing outside the package; they are intentional and stay dangling
until the optional packages are installed. Do not "fix" them. The warnings are prebuilt-ELF
noise (PIE/RELRO/unstripped), the setuid `chrome-sandbox`, and dlopen false positives.

## Version bumps

`update.sh` verifies Anthropic's signed `InRelease` against a pinned fingerprint, verifies
each `Packages` index against the SHA256 that `InRelease` signs for it, and takes the `.deb`
checksums from there — so the PKGBUILD's checksums are signed without downloading the `.deb`.

It rewrites `pkgver=`, `sha256sums_x86_64=` and `sha256sums_aarch64=` with `sed` anchored to
those exact line prefixes, and resets `pkgrel=1` only when the version actually changed.
**Do not reformat those three lines.** The plain `sha256sums=()` array for the two local
source files is deliberately separate and is not touched by those anchors.

`makepkg` does not refresh checksums for you: after editing `claude-desktop.sh` or
`claude-desktop-flags.conf`, update `sha256sums=()` by hand and regenerate `.SRCINFO`.

aarch64 is declared but cannot be built or tested here. Changes touching that branch are
unverified by construction — say so rather than implying otherwise.

## The launcher

`claude-desktop.sh` replaces upstream's `/usr/bin/claude-desktop` symlink and prepends
switches from `/etc/claude-desktop-flags.conf` and `~/.config/claude-desktop-flags.conf`.

Its one hard requirement: **nothing it does may stop the app from starting.** A conf path
that is a directory, a fifo, a broken symlink or unreadable is skipped, not fatal. With no
conf files it is a plain `exec`, byte-identical in behaviour to the symlink.

Known limitation, documented in the README and the shipped conf: flags do **not** reach a
session started by "Open at login". The app writes that autostart entry itself using
`process.execPath`, which is always the real binary, never `/usr/bin/claude-desktop`.

Test it with a harness rather than by launching the app — copy the script, redirect the
system conf path and replace the `exec` target with a stub that prints its argv.

## The update notifier

`check-update.sh` plus the units in `systemd/` are maintainer tooling, **not part of the
package** — they are not in `source=()` and are installed to `~/.config/systemd/user`.

Two stages, because no single signal means "a system upgrade is running": a path unit on
`/var/lib/pacman/db.lck` as a reliable but indiscriminate doorbell, then a filter that reads
the command line pacman logs for itself in `/var/log/pacman.log` and proceeds only for a
system upgrade. The filter fails open. A pacman hook cannot replace either stage — hooks run
around transactions, so they never see a bare `-Sy`, and their triggers match packages, not
the flags that caused the transaction.

`update.sh` prints progress on stderr and results on stdout precisely because
`check-update.sh` puts stdout into a desktop notification. Keep that separation.

## Verification habits worth keeping

- Diff the built package's file list against the previous build; the expected diff is
  usually small and any surprise is a real finding:
  `bsdtar -tf old.pkg.tar.zst | sort` vs the new one.
- Inspect the installed tree at `/usr/lib/claude-desktop/` for upstream questions —
  `objdump -p` for `NEEDED`, `strings`/`grep -aF` on `app.asar` for paths and spawned
  programs. `ugrep` chokes on long regexes against the asar; use fixed strings or Python.
- Comments in this repo make specific factual claims. If you change the code under one,
  change the comment, and verify the claim rather than carrying it forward.
