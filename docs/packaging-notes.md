# Packaging notes

Why this package does anything beyond unpacking Anthropic's `.deb`. Every
deviation below exists for a reason that was checked against the shipped
payload, and each one is a thing that could silently break on a version bump —
so they are written down rather than left in a commit message.

Start at [README.md](../README.md) if you just want to install or update it,
and at [CLAUDE.md](../CLAUDE.md) if you are about to change the packaging.

## What the packaging changes

The `.deb` payload under `/usr/lib/claude-desktop` is installed as-is. Only the
Debian-specific wrapping is dropped or translated, and one thing is added that
upstream has no place for (a flags file, below):

| Upstream `.deb` | Here |
| --- | --- |
| `postinst` registers Anthropic's apt repo, keyring and unattended-upgrades snippet | dropped — updates come from the AUR |
| `postinst` writes `/etc/apparmor.d/claude-desktop` | shipped as a packaged file, loaded by `.install` |
| `postinst` copies the GNOME Shell search provider out of `resources/` | shipped as packaged files (`.ini` + D-Bus `.service`) |
| `postinst` copies `resources/linux-mime/com.anthropic.Claude.xml` | shipped as a packaged file in `/usr/share/mime/packages/` |
| `postinst` links `/usr/bin/ccd` when the build ships `resources/bin/ccd` | same, created in `package()` when the file is there |
| `/usr/bin/claude-desktop` symlink to the Electron binary | launcher that prepends switches from a flags file, then execs the same binary |
| `chrome-sandbox` mode `4755` | preserved (`chmod 4755` in `package()`) |
| `/usr/share/lintian/overrides` | dropped |
| `/usr/share/doc/claude-desktop/copyright` | moved to `/usr/share/licenses/` |
| Debian `Depends`/`Recommends` | mapped to Arch `depends`/`optdepends` |

Upstream's `postinst` writes those three registrations itself because
`electron-installer-debian` cannot stage extra files. On Arch they are plain
package files instead, so pacman owns them, removes them on uninstall, and
triggers the `shared-mime-info` and `desktop-file-utils` hooks that rebuild the
MIME and desktop databases. The sources stay in place under `resources/`, which
is what the copied files point at.

The search provider puts recent chats and Claude Code sessions into GNOME's
Activities search. It is a GJS script, so it needs the `gjs` optional
dependency; the registration files are inert without it, and on every other
desktop.

The AppArmor profile is the same one upstream's `postinst` writes. It does not
confine the app: `flags=(unconfined)` only allowlists it for `CLONE_NEWUSER` on
systems that set `kernel.apparmor_restrict_unprivileged_userns=1`. Arch does not
enable AppArmor by default, so on a stock install the file is inert and Chromium
uses unprivileged user namespaces; the SUID `chrome-sandbox` remains as the
fallback. `claude-desktop-bin.install` loads it with `apparmor_parser` when
AppArmor is actually active, so it takes effect without a reboot, and unloads it
on removal.

## Command-line switches

Upstream's `/usr/bin/claude-desktop` is a bare symlink to the Electron binary,
so there is nowhere to put a switch that survives an upgrade: the desktop entry
is a package file, and edits to its `Exec=` line are overwritten on every
rebuild. This package installs a launcher there instead, which reads switches
from two optional files:

```
/etc/claude-desktop-flags.conf                       # shipped, all commented out
~/.config/claude-desktop-flags.conf                  # per-user, read second
```

One or more switches per line, `#` starts a comment. Lines are split on
whitespace and quoting is not interpreted, so a switch's value cannot contain
spaces. Switches from the files come before the command line, so anything
passed on the command line wins wherever Chromium takes the last occurrence.
With neither file present the launcher is a plain `exec` of the binary the
symlink used to point at, so the default behaviour is exactly upstream's.

The switch this exists for is `--force-device-scale-factor=`, which is the only
fix for blurry or uneven text on a fractionally scaled display and has no
environment-variable equivalent. Environment variables do not belong in the
flags file — export those from `~/.config/environment.d/`, which is also the
right place for Electron's own `ELECTRON_OZONE_PLATFORM_HINT=auto` if you want
the Wayland backend session-wide rather than per-app.

The AppArmor profile is unaffected: it attaches to
`/usr/lib/claude-desktop/claude-desktop`, the binary the launcher execs.

### The flags file does not reach a login-started session

Turning on *Open at login* makes the app write its own autostart entry, and it
records the running executable rather than the name on `$PATH`:

```
Exec="/usr/lib/claude-desktop/claude-desktop" --startup
```

That path is `process.execPath`, which Electron takes from `/proc/self/exe`,
so it is the real binary however the app was started — the launcher cannot put
itself there. A session started at login therefore gets none of the switches
from either flags file. Switches do apply when the app is started from the
desktop entry, a dock, a terminal, or a `claude://` link, and they survive the
app's own restarts (the GPU-crash and activation-token relaunches both rebuild
their argv from the running process, keeping user switches; only the
reset-app-data restart drops them).

If you rely on a switch and start the app at login, edit the `Exec=` line of
`~/.config/autostart/claude-desktop.desktop` to run `claude-desktop` instead.
That file belongs to your profile, not to this package, so nothing here can
manage it — and the app rewrites it whenever you toggle the setting.

## Cowork's sandbox VM on Arch

Cowork runs its sandbox inside a QEMU VM, and the app resolves that VM's host
tooling through paths hardcoded for Debian. Read out of `resources/app.asar`:

| Piece | Where the app looks |
| --- | --- |
| QEMU | `/usr/bin/qemu-system-x86_64` / `/usr/bin/qemu-system-aarch64` |
| Firmware (x86_64) | `/usr/share/OVMF/OVMF_CODE_4M.fd`, then `/usr/share/OVMF/OVMF_CODE.fd` |
| Firmware (aarch64) | `/usr/share/AAVMF/AAVMF_CODE.fd` |
| virtiofsd | `/usr/libexec/virtiofsd`, then `/usr/bin/virtiofsd` |

None of these has an environment variable or settings override, so a launcher
wrapper cannot fix them. The `virtiofsd` binary bundled under `resources/` is
only consulted when the host is Ubuntu 22.04, so it never applies on Arch.
Cowork treats the VM as unavailable unless all three resolve.

QEMU was looked up on `$PATH` until at least 3.1623.0; by 5.11492.5 it is a
fixed path too. Arch's `qemu-system-x86` and `qemu-system-aarch64` install to
exactly that path, so it needs no shim. Arch puts the other two elsewhere, so
the package ships compatibility symlinks:

* `/usr/bin/virtiofsd` → `../lib/virtiofsd`, since Arch's `virtiofsd` package
  installs to `/usr/lib/virtiofsd`.
* `/usr/share/edk2/OVMF_CODE_4M.fd` → `x64/OVMF_CODE.4m.fd` and the matching
  `OVMF_VARS_4M.fd`. `edk2-ovmf` ships `/usr/share/OVMF` as a symlink to
  `/usr/share/edk2`, so Debian-named links placed there are what the app
  resolves. The VARS path is derived from the CODE path by replacing
  `OVMF_CODE` with `OVMF_VARS`, so both names have to line up.

aarch64 needs no firmware shim: `edk2-aarch64` installs `AAVMF_CODE.fd` and
`AAVMF_VARS.fd` under `/usr/share/AAVMF`, exactly where the app looks.

The VM stack itself (`qemu-system-*`, the EDK2 firmware, `virtiofsd`) is an
optional dependency, mapping Debian's `Recommends` onto the Arch equivalent
rather than forcing QEMU on everyone who only wants to chat. The firmware is
declared per architecture — `edk2-ovmf` on x86_64, `edk2-aarch64` on aarch64 —
because both packages are `arch=any` and `edk2-ovmf` ships no AAVMF firmware,
so recommending it on aarch64 would name a package that cannot help. Until you install it those
symlinks dangle. They are inert in that state: the app probes them with
`access()` and reports the VM as unavailable, and nothing else on Arch looks in
`/usr/bin` for virtiofsd.

No group membership is needed for the VM. Arch's `50-udev-default.rules` gives
`/dev/kvm`, `/dev/vhost-vsock` and `/dev/vhost-net` mode `0666`, and declares a
`static_node` for each of the three, so `/dev/vhost-vsock` exists before
`vhost_vsock` is loaded and the kernel autoloads the module on first open.
Advice to add yourself to the `kvm` group or to `modprobe vhost_vsock` is
Debian/Ubuntu guidance, where those nodes are `0660 root:kvm`; on Arch it is a
no-op.

`namcap` reports all three as errors, and keeps reporting them even once the
optional packages are installed and the targets exist: it resolves symlinks
only inside the package tree, never against the live filesystem, and the
targets belong to other packages by design. Moving the three packages from
`optdepends` to `depends` is a one-line change if you would rather guarantee
Cowork works out of the box.

## Build-time assertions

Everything this PKGBUILD does beyond unpacking the payload rests on facts read
out of `resources/app.asar` and `resources/`: the paths the Cowork shims point
at, and the `Exec=` line of the GNOME search provider's D-Bus service. If
upstream moves any of them the package still builds and the feature silently
stops working, with nothing to notice it by.

So `package()` asserts them. It greps `app.asar` for each path it shims
(`/usr/bin/virtiofsd`, `/usr/libexec/virtiofsd`, the OVMF `CODE` path and the
`OVMF_VARS` name the second firmware link is derived from, or `AAVMF_CODE.fd`
on aarch64), for the QEMU path it relies on Arch already matching, and checks that the search provider's `Exec=` line still names
`/usr/bin/gjs` and a `searchProvider.js` inside this package's own prefix. A
version bump that changes one of them fails the build with a message naming
it, which is the moment someone is around to re-audit.

## Claude Code's sandboxed Bash

Separate from the Cowork VM, Claude Code's sandboxed Bash tool needs
[`bubblewrap`](https://github.com/containers/bubblewrap) for filesystem
isolation and `socat` for its network proxy relay. Both are optional
dependencies: without them the sandbox is unavailable and Claude Code falls back
to unsandboxed execution with a warning. `/sandbox` inside the app shows what is
missing.

## Updating

`update.sh` bumps the PKGBUILD to a release published in Anthropic's apt
repository. It does not download the ~180 MB `.deb`: the checksums come from the
repository's own package index, which it verifies first.

```bash
./update.sh              # bump to the newest published version
./update.sh 1.32352.1    # pin a specific version; the only way to downgrade
./update.sh --no-verify  # skip the OpenPGP check, trust HTTPS alone
./update.sh --check      # report only, change nothing
```

`--check` prints one line comparing what upstream publishes against the
`PKGBUILD` and the installed package, and exits `0` when there is nothing to
do, `10` when a newer release exists, `11` when the `PKGBUILD` is current
but the installed package is behind it, or `12` when the newest published
version is older than the `PKGBUILD`'s — with the index verified and
unexpired, most likely upstream withdrawing a release. `check-update.sh`
raises a notification for `12` too. A plain `./update.sh` refuses to move
the `PKGBUILD` backwards in that case; name the version to do it anyway.

The trust chain matches what `apt` itself does:

1. `dists/stable/InRelease` is verified with `gpgv` against Anthropic's release
   key, pinned to fingerprint `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`.
   Everything after that reads only the signed text `gpgv` writes out, never
   the file itself, which can carry unsigned lines around the signature, and
   the index is refused once its signed `Valid-Until` has passed, so a mirror
   cannot replay an old one to hide newer releases.
2. Each `main/binary-*/Packages` index is verified against the SHA256 that the
   signed `InRelease` lists for it.
3. The per-architecture `.deb` SHA256 values written into the PKGBUILD are read
   from those verified indexes.

`makepkg` then checks the downloaded `.deb` against those values at build time.

The script also refuses to continue if upstream moves the pool path that the
PKGBUILD constructs its download URL from, or if the newest version differs
between the two architectures.

### Getting told about a new release

Nothing polls for you by default. `systemd/` holds a user path unit that runs
`./check-update.sh` after a `pacman -Syu` or `yay -Syu`, which raises a desktop
notification if a newer release has been published:

```bash
mkdir -p ~/.config/systemd/user
for u in path service; do
  sed "s|@CHECKOUT@|$PWD|g" systemd/claude-desktop-update-check.$u \
    > ~/.config/systemd/user/claude-desktop-update-check.$u
done
systemctl --user daemon-reload
systemctl --user enable --now claude-desktop-update-check.path
```

Run it from the root of the checkout. The units in `systemd/` leave the
checkout's path as `@CHECKOUT@`, and the `sed` fills it in, so the installed
copies point at wherever you cloned it. Systemd has no specifier for "the
directory this unit file came from", and `%h` would only fix the home
directory, not the folder name. Run it again if the checkout moves.

It works in two stages, because no single signal means "a system upgrade is
running".

**The doorbell** is `/var/lib/pacman/db.lck`, the lock pacman takes for every
operation that writes. That makes it reliable — it catches `-Syu` whatever
else the run does — but indiscriminate: `-U`, `-S pkg` and `-R` ring it too.

`PathExists=` does not ring once per run by itself. When the triggered service
exits, systemd checks the path again at once and restarts the service if the
lock is still there (`systemd.path(5)`). The check takes milliseconds, so a
long transaction used to restart it five times in a row, trip the service's
start limit, and fail the path unit with it. After that it ignored every
pacman run until `systemctl --user reset-failed`. So the service now stays
active until the lock is gone: `ExecStart=` runs the check under a 120 s cap,
then `ExecStartPost=` waits for `db.lck` to disappear. A stale lock left by a
crashed pacman keeps it waiting, which costs one sleeping shell.

**The filter** is `/var/log/pacman.log`, where pacman records its own command
line as it starts (`[PACMAN] Running 'pacman -Syu'`, and for yay something
like `pacman --config /tmp/… -Syu --needed …`). `check-update.sh` reads the
last such line and goes no further unless it names a system upgrade — a `-S`
cluster together with a `u`, or `--sync --sysupgrade`. A non-upgrade run exits
in about 3 ms having touched nothing, not even the rate-limit stamp.

The filter fails open: an unreadable log or a line it cannot parse means the
check runs anyway, so it only ever drops invocations it positively recognised
as something else. Bare `pacman -Sy` is among them, deliberately — a refresh
without an upgrade leaves a partial-upgrade state nobody should be courting on
Arch. Drop the `u` requirement in `_is_sysupgrade` if you disagree.

The check runs beside the pacman run that triggered it, out of process, so it
cannot slow `-Syu` down — but it also cannot print into that terminal, hence
the notification. `~/.cache/claude-desktop-update/status` keeps the last
result, and a floor of ten minutes between checks (override with
`CLAUDE_UPDATE_MIN_INTERVAL`) stops a run of pacman commands from hammering the
index. Failures are deliberately silent, since the usual cause is the network
being down, which pacman itself will have just complained about.

Neither stage can be replaced by a **pacman hook**. A hook cannot see a bare
`pacman -Sy` at all — hooks run before or after a *transaction*, and a database
sync with no targets is not one — and it cannot distinguish `-Syu` from any
other upgrade either, because a trigger matches the packages in a transaction,
never the flags that caused it. `Operation = Upgrade` fires just as happily for
`pacman -U`. **Watching `/var/lib/pacman/sync`** is no better: pacman only
rewrites a database it actually re-downloaded, so a `-Syu` with nothing new
upstream would be invisible.

The one gap: systemd evaluates `PathExists` after the inotify event, so a
pacman operation that takes and drops the lock faster than that can slip
through. Any `-Syu` does network I/O and holds it long enough; a no-op local
command might not — and those are filtered out anyway.

`./check-update.sh --force` ignores the rate limit, for testing.

## Notes

* **Updates are not automatic.** The Linux app has no built-in updater, and the
  apt repository that would normally deliver updates is deliberately not
  registered. Rebuild from this repository to upgrade, or let the path unit
  above tell you when there is something to rebuild.
* **Not everything from macOS/Windows is in the Linux beta**: no Computer Use,
  no dictation, and the Quick Entry hotkey needs the GlobalShortcuts portal on
  native Wayland.
* **Cowork's sandboxed VM** needs the `qemu-system-*`, EDK2 firmware and
  `virtiofsd` optional dependencies. The firmware package differs per
  architecture: `edk2-ovmf` on x86_64, `edk2-aarch64` on aarch64.
* **`libpipewire` is a hard dependency**, matching upstream. WebRTC dlopens
  `libpipewire-0.3.so.0` for screen sharing and camera, and Anthropic's own
  `claude-native-binding.node` carries it as a `NEEDED` entry — so a missing
  libpipewire fails that native module's load, not just the device list.
* **Sign-in** works with a claude.ai subscription or organization SSO. The
  desktop app does not accept a Claude Console API key; use the CLI for that.
* The app is proprietary. This repository contains packaging only; it downloads
  the binary from Anthropic at build time and redistributes nothing.

## Prior art

Several AUR packages track the same upstream `.deb`, and the Cowork path shims
here match what they independently arrived at.

* [`claude-desktop`](https://aur.archlinux.org/packages/claude-desktop) — the
  most-used one. Same `.deb`, same Cowork shims; declares
  `conflicts=('claude-desktop-bin')`. It makes the Cowork VM stack and
  `bubblewrap`/`socat` hard dependencies rather than optional, which this
  package deliberately does not. **The flags file here is its idea**, under the
  same path, minus its automatic Wayland switch: that one is better handled by
  `ELECTRON_OZONE_PLATFORM_HINT` in the environment, and changing the display
  backend by default is not this package's call.
* [`ya-claude`](https://aur.archlinux.org/packages/ya-claude) — verifies the
  signed apt index inside `prepare()` at build time, with the release key
  committed as a source file, instead of at bump time like `update.sh` here.
  Worth knowing about if you would rather every build re-derive the `.deb`
  checksum from Anthropic's signature than trust the one in the `PKGBUILD`.
* [`claude-desktop-extra`](https://aur.archlinux.org/packages/claude-desktop-extra)
  — not a plain repackage: it ships a patched `app.asar` from its own
  pre-built tarball, adding Computer Use bridges, themes and multi-profile
  support. Useful as a reference for what the app pulls in at runtime, not as
  a comparison for this package. **The build-time assertions above are its
  idea**, generalised from the one check it makes on the search provider to
  every path this package shims.

Neither Anthropic nor the AUR ships an official Arch package. The `.deb` in
the documented apt repository is the only published Linux build: upstream's
maintainer scripts mention an rpm, but no rpm, AppImage or Flatpak is
published, and the docs list Fedora and RHEL as not yet supported.

### If this is ever published as `claude-desktop-bin`

The name is free on the AUR — it used to be `claude-desktop-extra`'s, before
that package was renamed. But it still carries `replaces=('claude-desktop-bin')`
from the migration. An AUR helper does not act on `replaces` for a package it
builds from source, so an AUR publication is unaffected; anyone subscribed to
that project's own signed pacman repository, however, would be offered a
silent migration off a package of this name. Worth knowing before adopting it.

`conflicts=('claude-desktop')` here already covers all three of them, since
each one `provides` that name — no per-package `conflicts` entries needed.
