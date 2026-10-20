# claude-desktop-bin

Arch packaging for the official Claude desktop app. Anthropic ships Linux builds
only as `.deb` ([docs](https://code.claude.com/docs/en/desktop-linux)); this
repackages that `.deb` unmodified, so the Electron bundle you run is byte for
byte the one Anthropic signed. `x86_64` and `aarch64`.

```bash
makepkg -si
```

Or `./install.sh`, which builds, installs, and then offers the optional feature
groups (Cowork's VM, Claude Code's sandboxed Bash, tray icon menu). `-y` accepts
all of them, `--dry-run` prints what it would do.

## Updating

```bash
./update.sh && ./install.sh
```

`update.sh` bumps the PKGBUILD to the newest published release, taking the `.deb`
checksums from Anthropic's signed apt index instead of downloading the ~180 MB
`.deb` to hash it. `./update.sh --check` reports without changing anything.

Nothing updates itself — the app has no built-in updater, and the apt repo that
would normally deliver updates is deliberately not registered. To get told when
there is something to rebuild, enable the path unit in `systemd/`, which checks
after a `pacman -Syu` and raises a notification only if a newer release exists.

## What it does beyond unpacking

* Reproduces the parts of upstream's `postinst` that apply here: the AppArmor
  userns profile, the GNOME Shell search provider, the `.mcpb`/`.skill` MIME
  types. Drops the apt repository registration.
* Symlinks the paths Cowork hardcodes for Debian — OVMF firmware and
  `virtiofsd` — to where Arch actually puts them. Without these, Cowork reports
  its VM as unavailable.
* Replaces upstream's `/usr/bin/claude-desktop` symlink with a launcher that
  reads switches from `~/.config/claude-desktop-flags.conf`, so something like
  `--force-device-scale-factor=` survives an upgrade. Behaves exactly like the
  symlink when that file does not exist.
* Asserts, at build time, every upstream path and filename the above depends on,
  so a version bump that moves one fails the build instead of silently shipping
  a dead symlink.

## Worth knowing

* **Cowork's VM** needs the `qemu-system-*`, EDK2 firmware and `virtiofsd`
  optional dependencies. No `kvm` group membership is needed on Arch.
* **Flags do not reach a session started by "Open at login"** — the app writes
  that autostart entry itself, pointing at the real binary.
* **`namcap` reports three symlink errors.** They are intentional.
* The app is proprietary. This repository is packaging only; it downloads the
  binary from Anthropic at build time and redistributes nothing.

[docs/packaging-notes.md](docs/packaging-notes.md) has the reasoning behind all
of the above — what upstream hardcodes, how the trust chain works, what the
other AUR packages do differently. [CLAUDE.md](CLAUDE.md) is the orientation for
anyone, human or otherwise, about to change the packaging.
