# claude-desktop-bin

Arch Linux packaging for Anthropic's official Claude desktop app. Anthropic ships
the Linux build only as a `.deb` in its apt repository, as its
[Linux docs](https://code.claude.com/docs/en/desktop-linux) describe. This
repository turns that `.deb` into a pacman package and leaves the Electron bundle
inside it untouched.

The PKGBUILD declares `x86_64` and `aarch64`. Only `x86_64` has been built and
tested.

## Install

```bash
git clone https://github.com/movsq/claude-desktop-arch.git
cd claude-desktop-arch
makepkg -si
```

`./install.sh` does the same build and install, then asks about three groups of
optional packages: Cowork's sandbox VM, Claude Code's sandboxed Bash, and the tray
icon menu. Pass `-y` to take all three, `-n` to skip them, or `--dry-run` to print
the commands without running them.

## Update

Nothing updates on its own. The app has no built-in updater on Linux, and this
package leaves Anthropic's apt repository unregistered, so you rebuild when a new
release comes out:

```bash
./update.sh && ./install.sh
```

`update.sh` bumps the PKGBUILD to the newest published version. It reads the
`.deb` checksums from Anthropic's apt index after checking the index's OpenPGP
signature against a pinned key, so you never download the roughly 180 MB `.deb`
just to hash it. `makepkg` then rejects any download that doesn't match.

`./update.sh --check` reports the published, PKGBUILD and installed versions and
changes nothing. To go back to an older release, name it, as in
`./update.sh 3.1623.0`. A bare `./update.sh` refuses to downgrade.

### Getting a notification

`systemd/` has a user path unit that runs the check after every `pacman -Syu` or
`yay -Syu` and raises a desktop notification when there is something to do,
usually a new release. Otherwise it stays silent.

Run this from the root of your checkout. The `sed` fills in the checkout's path,
which the units in the repository leave as `@CHECKOUT@`.

```bash
mkdir -p ~/.config/systemd/user
for u in path service; do
  sed "s|@CHECKOUT@|$PWD|g" systemd/claude-desktop-update-check.$u \
    > ~/.config/systemd/user/claude-desktop-update-check.$u
done
systemctl --user daemon-reload
systemctl --user enable --now claude-desktop-update-check.path
```

If you move the checkout later, run it again from the new place.

## What the package changes

The payload in `/usr/lib/claude-desktop` goes in as Anthropic built it. The
changes are all in the Debian wrapping around it.

- Anthropic's `postinst` registers an AppArmor userns profile, a GNOME Shell search
  provider and the `.mcpb`, `.dxt` and `.skill` MIME types, and links
  `/usr/bin/ccd` in builds that include it. Here those are package files that
  pacman owns and removes. The apt repository registration is dropped.
- Cowork looks for its VM firmware and `virtiofsd` at Debian paths with no way to
  override them. The package adds symlinks from those paths to where Arch installs
  the same files. Without them Cowork says its VM is unavailable.
- `/usr/bin/claude-desktop` is a small launcher instead of a symlink. It adds the
  switches listed in `/etc/claude-desktop-flags.conf` and
  `~/.config/claude-desktop-flags.conf`, so a fix like
  `--force-device-scale-factor=1.5` survives upgrades. With neither file it
  behaves exactly like the symlink.
- At build time, `package()` checks that every upstream path and file name the
  steps above rely on is still there. If a release moves one, the build fails and
  names it. Without that check the package would ship a symlink to nothing and
  Cowork would break with no error.

## Known issues

- Cowork's VM needs the optional `qemu-system-*`, EDK2 firmware and `virtiofsd`
  packages. You don't need to join the `kvm` group on Arch.
- The flags file has no effect when the app starts through "Open at login". The app
  writes that autostart entry itself and points it at the real binary. Edit
  `~/.config/autostart/claude-desktop.desktop` to run `claude-desktop` if you need
  your switches there.
- `namcap` reports three errors, one per Cowork symlink. They point at files from
  the optional packages, so they dangle until you install those. That's expected.

## Further reading

[docs/packaging-notes.md](docs/packaging-notes.md) explains each decision above,
including what upstream hardcodes, how the signature check works and how other AUR
packages handle the same `.deb`. [CLAUDE.md](CLAUDE.md) is the starting point for
anyone changing the packaging, human or agent.

## License

The packaging files in this repository are under [0BSD](LICENSE). Claude Desktop
itself is proprietary Anthropic software. This repository doesn't contain it, and
the build downloads it from Anthropic.
