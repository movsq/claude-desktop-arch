# Maintainer: movsq

# Repackages Anthropic's official .deb from the apt repository documented at
# https://code.claude.com/docs/en/desktop-linux
# Nothing is rebuilt: the Electron bundle is shipped as-is, only the Debian
# packaging around it (apt repo registration, lintian overrides) is dropped.

pkgname=claude-desktop-bin
_pkgname=claude-desktop
pkgver=5.11492.5
pkgrel=1
pkgdesc='Claude desktop app: Chat, Cowork and Claude Code in one window (official Anthropic build)'
arch=('x86_64' 'aarch64')
url='https://claude.ai/download'
license=('LicenseRef-Anthropic-Proprietary')
provides=("${_pkgname}=${pkgver}")
conflicts=("${_pkgname}")
options=('!strip' '!debug')
backup=('etc/apparmor.d/claude-desktop' 'etc/claude-desktop-flags.conf')
install="${pkgname}.install"

# Direct NEEDED entries of usr/lib/claude-desktop/claude-desktop, plus:
#   libsecret, libnotify   no NEEDED entry, but the sonames are dlopen strings
#                          in the binary, and upstream declares both.
#   libpipewire            a hard NEEDED of resources/app.asar.unpacked/
#                          node_modules/@ant/claude-native/
#                          claude-native-binding.node, and separately dlopen'd
#                          by WebRTC's portal capturer. The one that is easy
#                          to miss: absent, the native module fails to load,
#                          not just the screen-share device list.
#   libcap-ng, libseccomp  NEEDED by the virtiofsd bundled under resources/.
#   libdrm, libxtst,       no NEEDED entry and no soname string anywhere in
#   util-linux-libs        the payload. Kept on upstream's authority alone --
#                          its Depends lists libdrm2, libxtst6 and libuuid1 --
#                          which is why namcap reports all three as possibly
#                          unneeded. Prune only against upstream, not against
#                          the ELF headers.
depends=(
  'alsa-lib'
  'at-spi2-core'
  'cairo'
  'dbus'
  'expat'
  'glib2'
  'glibc'
  'gtk3'
  'hicolor-icon-theme'
  'libcap-ng'
  'libcups'
  'libdrm'
  'libgcc'
  'libnotify'
  'libpipewire'
  'libseccomp'
  'libsecret'
  'libstdc++'
  'libx11'
  'libxcb'
  'libxcomposite'
  'libxdamage'
  'libxext'
  'libxfixes'
  'libxkbcommon'
  'libxrandr'
  'libxtst'
  'mesa'
  'nspr'
  'nss'
  'pango'
  'systemd-libs'
  'util-linux-libs'
  'xdg-desktop-portal'
  'xdg-utils'
)

optdepends=(
  'libdbusmenu-glib: context menu for the tray icon'
  'gnome-keyring: credential storage backend for libsecret'
  'kwallet: credential storage backend on KDE Plasma'
  'xdg-desktop-portal-gtk: portal backend for GTK-based desktops'
  'xdg-desktop-portal-gnome: portal backend for GNOME'
  'xdg-desktop-portal-kde: portal backend for KDE Plasma'
  'gjs: GNOME Shell search provider for chats and Claude Code sessions'
  'gvfs: move files to trash from the app'
  'trash-cli: move files to trash from the app'
  'libpulse: audio output, via PulseAudio or pipewire-pulse'
  'libspeechd: text-to-speech'
  'libva: hardware-accelerated video decoding'
  'vulkan-icd-loader: hardware-accelerated rendering via Vulkan'
  'apparmor: load the shipped userns profile when AppArmor is enabled'
  'virtiofsd: host directory sharing for the Cowork sandbox VM'
  'bubblewrap: filesystem isolation for Claude Code sandboxed Bash'
  'socat: network proxy relay for Claude Code sandboxed Bash'
  'openssh: system ssh client for Claude Code remote sessions'
)
# Both edk2 packages are arch=any, so edk2-ovmf installs happily on aarch64
# and ships no AAVMF firmware at all -- recommending it there would send
# people to a package that cannot help them. The firmware has to be named per
# arch, and install.sh offers the same pair this declares.
optdepends_x86_64=('qemu-system-x86: sandboxed VM for Cowork'
                   'edk2-ovmf: UEFI firmware for the Cowork sandbox VM')
optdepends_aarch64=('qemu-system-aarch64: sandboxed VM for Cowork'
                    'edk2-aarch64: UEFI firmware for the Cowork sandbox VM')

_repo='https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop'
source=('claude-desktop.sh' 'claude-desktop-flags.conf')
source_x86_64=("${_pkgname}-${pkgver}-amd64.deb::${_repo}/${_pkgname}_${pkgver}_amd64.deb")
source_aarch64=("${_pkgname}-${pkgver}-arm64.deb::${_repo}/${_pkgname}_${pkgver}_arm64.deb")
noextract=("${_pkgname}-${pkgver}-amd64.deb" "${_pkgname}-${pkgver}-arm64.deb")

sha256sums=('51dde82e033e475ec0326b91cb3fa7124898b07069a4c473cbee1bcc1df4a19c'
            '97dc3edd77a9643d1e5dc70fd463cdf82b4281372506df2242cc68a82c32ec4a')
# Mirrors the SHA256 published in the repository's Packages index.
sha256sums_x86_64=('b96208b207e450b740f7dbe304f6077fed80e7f3d37ddd545991c4e8201564cf')
sha256sums_aarch64=('fe6cd8a70f96b96eb4e6b647300cfaee6aaff4ce133a0fbbe11c2cdb775f5a6a')

_debarch() {
  [[ $CARCH == aarch64 ]] && echo arm64 || echo amd64
}

prepare() {
  # Glob the member: dpkg-deb picks the payload compression, and Debian
  # tooling has been migrating from xz to zstd.
  bsdtar -xf "${srcdir}/${_pkgname}-${pkgver}-$(_debarch).deb" -C "${srcdir}" 'data.tar.*'
}

package() {
  bsdtar -xpf "${srcdir}"/data.tar.* -C "${pkgdir}" --no-same-owner ./usr

  # The Chromium SUID sandbox helper. Arch allows unprivileged user
  # namespaces, so Chromium normally uses those, but keep the helper as the
  # fallback path upstream relies on.
  chmod 4755 "${pkgdir}/usr/lib/${_pkgname}/chrome-sandbox"

  # --- Cowork VM compatibility ------------------------------------------
  # The Cowork sandbox VM resolves its host tooling through paths hardcoded
  # for Debian. From resources/app.asar:
  #   qemu       /usr/bin/qemu-system-x86_64 (arm64: /usr/bin/qemu-system-aarch64)
  #   firmware   /usr/share/OVMF/OVMF_CODE_4M.fd, /usr/share/OVMF/OVMF_CODE.fd
  #              (arm64: /usr/share/AAVMF/AAVMF_CODE.fd)
  #   virtiofsd  /usr/libexec/virtiofsd, /usr/bin/virtiofsd
  # None of these has an environment or settings override, and the virtiofsd
  # bundled under resources/ is only consulted on Ubuntu 22.04, so without
  # these links Cowork reports its VM as unavailable on Arch. qemu needs no
  # link: Arch's qemu-system-* packages install to the same /usr/bin path.

  # Everything in this section rests on those strings still being in
  # app.asar. When upstream moves one, the package goes on building and
  # Cowork silently reports no VM, so assert them here: a bump that changes
  # them fails the build instead, which is when there is someone to read it.
  local _asar="${pkgdir}/usr/lib/${_pkgname}/resources/app.asar"
  # Arch's CARCH values are exactly qemu's binary suffixes, on both arches.
  local _want=('/usr/bin/virtiofsd' '/usr/libexec/virtiofsd'
               "/usr/bin/qemu-system-${CARCH}")
  if [[ $CARCH == x86_64 ]]; then
    # The CODE path the links are named after, and the replace() call that
    # derives the VARS path from it -- which is what makes OVMF_VARS_4M.fd the
    # right name for the second link. Matching the call and not the bare
    # OVMF_VARS name is deliberate: upstream swapping the derivation for an
    # explicit path list is exactly the drift that would invalidate that name,
    # and a bare name would still match afterwards.
    _want+=('/usr/share/OVMF/OVMF_CODE_4M.fd' 'OVMF_CODE","OVMF_VARS')
  else
    _want+=('/usr/share/AAVMF/AAVMF_CODE.fd')
  fi
  local _s
  for _s in "${_want[@]}"; do
    grep -qaF -- "$_s" "$_asar" || {
      echo "==> app.asar no longer references '${_s}'; re-audit the Cowork shims" >&2
      return 1
    }
  done

  # Arch installs virtiofsd as /usr/lib/virtiofsd; neither searched path exists.
  ln -s ../lib/virtiofsd "${pkgdir}/usr/bin/virtiofsd"

  if [[ $CARCH == x86_64 ]]; then
    # edk2-ovmf ships /usr/share/OVMF as a symlink to /usr/share/edk2, so
    # Debian-named links placed in /usr/share/edk2 are what the app resolves.
    # The VARS template is derived from the CODE path by replacing OVMF_CODE
    # with OVMF_VARS, so both names have to line up.
    install -dm755 "${pkgdir}/usr/share/edk2"
    ln -s x64/OVMF_CODE.4m.fd "${pkgdir}/usr/share/edk2/OVMF_CODE_4M.fd"
    ln -s x64/OVMF_VARS.4m.fd "${pkgdir}/usr/share/edk2/OVMF_VARS_4M.fd"
  fi
  # aarch64 needs no firmware shim: edk2-aarch64 installs AAVMF_CODE.fd and
  # AAVMF_VARS.fd under /usr/share/AAVMF, exactly where the app looks.

  # --- the rest of upstream's postinst ----------------------------------
  # Its `configure` step registers five things. The apt repository (keyring,
  # sources entry, unattended-upgrades snippet) is deliberately dropped --
  # updates come from the AUR -- and the AppArmor profile is below. The other
  # three are reproduced here as packaged files, so pacman owns them and
  # removes them again. All three sources stay in place under resources/,
  # exactly where the copies reference them.

  # GNOME Shell search provider: an .ini the shell reads and a D-Bus service
  # that starts the bundled GJS script on demand. Its Exec line points at
  # /usr/bin/gjs and at searchProvider.js under /usr/lib/claude-desktop,
  # which is this package's layout too, so nothing has to be rewritten --
  # the two checks below are what makes that claim true at build time rather
  # than at the time the comment was written. Without them a reworked Exec
  # line would register a D-Bus service pointing at nothing.
  local _sp="${pkgdir}/usr/lib/${_pkgname}/resources/gnome-search-provider"
  grep -qxF -- \
    "Exec=/usr/bin/gjs -m /usr/lib/${_pkgname}/resources/gnome-search-provider/searchProvider.js" \
    "${_sp}/com.anthropic.Claude.SearchProvider.service" || {
    echo "==> the search provider's .service Exec line changed; re-audit" >&2
    return 1
  }
  [[ -f ${_sp}/searchProvider.js ]] || {
    echo "==> resources/gnome-search-provider/searchProvider.js is gone; re-audit" >&2
    return 1
  }

  install -Dm644 \
    "${pkgdir}/usr/lib/${_pkgname}/resources/gnome-search-provider/com.anthropic.Claude.search-provider.ini" \
    "${pkgdir}/usr/share/gnome-shell/search-providers/com.anthropic.Claude.search-provider.ini"
  install -Dm644 \
    "${pkgdir}/usr/lib/${_pkgname}/resources/gnome-search-provider/com.anthropic.Claude.SearchProvider.service" \
    "${pkgdir}/usr/share/dbus-1/services/com.anthropic.Claude.SearchProvider.service"

  # The .mcpb/.dxt extension and .skill bundle types, which the shipped
  # desktop entry already declares under MimeType. shared-mime-info rebuilds
  # the database from its own pacman hook; it is a gtk3 dependency, so it is
  # always installed here.
  install -Dm644 \
    "${pkgdir}/usr/lib/${_pkgname}/resources/linux-mime/com.anthropic.Claude.xml" \
    "${pkgdir}/usr/share/mime/packages/com.anthropic.Claude.xml"

  # /usr/bin/ccd, the bundled terminal launcher for Claude Code. Only some
  # builds ship resources/bin/ccd, and upstream's postinst likewise creates
  # the link only when the file is there.
  if [[ -x ${pkgdir}/usr/lib/${_pkgname}/resources/bin/ccd ]]; then
    ln -s "../lib/${_pkgname}/resources/bin/ccd" "${pkgdir}/usr/bin/ccd"
  fi

  # --- flags file -------------------------------------------------------
  # Replaces upstream's /usr/bin/claude-desktop symlink with a launcher that
  # prepends switches read from /etc/claude-desktop-flags.conf and
  # ~/.config/claude-desktop-flags.conf. Without those files it is a plain
  # exec of the same binary the symlink pointed at, so the default behaviour
  # is unchanged; with them there is somewhere to keep a switch like
  # --force-device-scale-factor that an upgrade will not overwrite. The
  # desktop entry's `Exec=claude-desktop` and the AppArmor profile both still
  # resolve the same way: the profile attaches to the real binary below.
  rm -f "${pkgdir}/usr/bin/${_pkgname}"
  install -Dm755 "${srcdir}/${_pkgname}.sh" "${pkgdir}/usr/bin/${_pkgname}"
  install -Dm644 "${srcdir}/${_pkgname}-flags.conf" \
    "${pkgdir}/etc/${_pkgname}-flags.conf"

  # Debian-only packaging artefacts.
  rm -rf "${pkgdir}/usr/share/lintian"

  install -Dm644 "${pkgdir}/usr/share/doc/${_pkgname}/copyright" \
    "${pkgdir}/usr/share/licenses/${pkgname}/copyright"
  install -Dm644 "${pkgdir}/usr/lib/${_pkgname}/LICENSES.chromium.html" \
    "${pkgdir}/usr/share/licenses/${pkgname}/LICENSES.chromium.html"
  rm -rf "${pkgdir}/usr/share/doc"

  # Same profile upstream's postinst writes. It does not confine the app;
  # flags=(unconfined) only allowlists it for CLONE_NEWUSER on systems that
  # set kernel.apparmor_restrict_unprivileged_userns=1. Inert when AppArmor
  # is not enabled.
  install -dm755 "${pkgdir}/etc/apparmor.d"
  cat > "${pkgdir}/etc/apparmor.d/${_pkgname}" <<-EOF
	abi <abi/4.0>,
	include <tunables/global>

	profile ${_pkgname} /usr/lib/${_pkgname}/${_pkgname} flags=(unconfined) {
	  userns,

	  include if exists <local/${_pkgname}>
	}
	EOF
  chmod 644 "${pkgdir}/etc/apparmor.d/${_pkgname}"
}
