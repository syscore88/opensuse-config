# 🦎 openSUSE Tumbleweed Post-Install Setup Script

A comprehensive, automated Bash post-installation script for a fresh **openSUSE Tumbleweed** install. It configures Zypper repositories (Packman, Games, Emulators/Wine, Google Chrome, Brave), removes the default KDE Plasma/GNOME apps (mail, calendar, multimedia), installs a large set of system/multimedia/gaming packages, detects your GPU and picks matching drivers plus 32-bit libraries, sets up virtualization (libvirt/QEMU) and the firewall, zeroes out the `systemd-boot` timeout, forces Cloudflare DNS 1.1.1.2/1.0.0.2, and installs Zsh with Oh My Zsh and Powerlevel10k.

The script auto-detects the message language (Polish/English) from the `LANG`/`LC_ALL`/`LC_MESSAGES` locale variables and shows all logs and the progress bar in the detected language.

---

## 🚀 Script Features

- **Temporary Passwordless Sudo**: Requests the admin password once at the start, then configures a temporary `NOPASSWD` rule (via `/etc/sudoers.d/`, or a `polkit`/`run0` rule on systems without `visudo`) so the rest of the script can run unattended. The rule is automatically removed at the end.
- **Self-Healing Repositories**: Stops PackageKit before package operations, adds the Packman, Games, Emulators/Wine, Google Chrome, and Brave repositories (importing GPG keys, with an automatic fallback to fetching Brave's key from a keyserver if the standard import fails), then performs a full system upgrade (`zypper dup --allow-vendor-change`).
- **Default Bloatware Removal**: Removes (if installed) KDE mail/PIM apps (Kontact, KMail, Akonadi, KOrganizer, KAddressBook, Akregator), GNOME/KDE browsers and multimedia apps (Konqueror, Epiphany, Evolution, GNOME Music/Maps/Weather/Contacts/Calendar/Clocks, Rhythmbox, Elisa, Dragon Player, Showtime, Parole), and others (nano, Plasma Welcome, Plasma Vault/Thunderbolt/Browser Integration, Kontrast, KRDP/KRFB), then cleans up the related config, cache, and user data directories. If Plasma is detected, it also disables KWallet.
- **Package Installation**: Installs a large `PACKAGES` set covering browsers (Chrome, Brave), media/creative apps (GIMP, Kdenlive, Mixxx, Audacity, Kolourpaint, SoundConverter, HandBrake, VLC with codecs, qmmp...), messaging and torrents (Telegram, qBittorrent, Thunderbird), dev tools (`cmake`, `meson`, `patterns-devel-base-devel_basis`, `kernel-devel`), and the gaming stack (`gamemode`, `gamescope`, `mangohud`, `goverlay`, `libvkd3d1`, Wine Staging/Mono/Gecko) — with an automatic fallback to the Packman repository for packages unavailable in the default repos.
- **CDEmu**: Installs `cdemu-daemon`/`cdemu-client`, but disables and masks the service and hides its autostart entries so it doesn't run in the background.
- **GPU Detection & Driver Setup**: Detects NVIDIA/AMD/Intel GPUs via `lspci`, installs the matching 32-bit Mesa/Vulkan libraries (or vendor-specific packages), writes the detected kernel modules into the Dracut configuration (`force_drivers`), and rebuilds the initramfs.
- **Standalone Packages**: Downloads and installs Discord as an RPM (from Packman if available, otherwise directly from the official download endpoint), plus `ls-fg`/`ls-fg-vk` and Faugus Launcher — the latest releases fetched automatically via the GitHub Releases API.
- **Extra Dependencies**: Installs `python3-gobject`, `python3-Pillow`, `python3-psutil`, `python3-requests`, `libcanberra-gtk3-module`, `vulkan-tools`, `ImageMagick`, and the Python packages `vdf`, `icoextract`, `pygame` via `pip3`.
- **Virtualization & Firewall**: Installs `virt-manager`, QEMU (auto-detecting the available package: `qemu-kvm`/`qemu-x86`/`qemu`), `libvirt`, `libvirt-daemon-qemu`, and OVMF/EDK2 (if available); imports default `virt-manager` GUI preferences via `dconf load`; enables `libvirtd`/`virtqemud`; defines/starts/autostarts the default libvirt NAT network; configures `firewalld` (adds `virbr0` to the `libvirt` zone and allows traffic from the `192.168.122.0/24` subnet); adds the user to the `libvirt`/`kvm` groups.
- **System Tuning & DNS**: Enables `fstrim.timer`, vacuums the journal to 2 days, zeroes out the `systemd-boot` timeout (editing `loader.conf` + `bootctl set-timeout 0`), then forces Cloudflare (`1.1.1.1`/`1.0.0.1` + IPv6) as the system and NetworkManager DNS and applies it to the active connection.
- **Shell Setup**: Installs Zsh (if missing), sets it as the default shell, installs Oh My Zsh (unattended) and the Powerlevel10k theme, adds the `zsh-autosuggestions`/`zsh-syntax-highlighting` plugins, and updates `~/.zshrc` (theme, plugins, detected system locale, `fastfetch` on login).
- **Dotfiles & Config Copy**: Copies an optional `.update.sh` helper script plus `.local`/`.config` directories from the script folder into the user's home directory.
- **Progress Bar & Logging**: Displays a live progress bar across 3 phases / 12 steps. On failure, a detailed log is saved to `~/install_error_<timestamp>.log`.
- **Optional Reboot Prompt**: Asks **"Do you want to restart the system now? [Y/N]"** at the end instead of forcing a reboot.

---

## 🔍 Module Details

### 1. Preparation & Repositories (Phase 1/3)
Copies dotfiles, grants temporary `NOPASSWD` sudo, installs base tools (`curl`, `wget`, `pciutils`, `gpg2`, `dconf`), adds the Packman, Games, Emulators/Wine, Google Chrome, and Brave repositories (with GPG key verification), runs a full system upgrade (`zypper dup`), then removes the default KDE/GNOME mail and multimedia apps along with their data and configuration — disabling KWallet if Plasma is detected.

### 2. Package & 32-bit Library Installation (Phase 2/3)
Installs Chrome and Brave, then a large set of system/multimedia/gaming/dev packages (with a Packman fallback), disables and masks CDEmu, detects the GPU vendor and installs the matching 32-bit libraries plus Dracut/initramfs configuration, downloads and installs Discord, `ls-fg`/`ls-fg-vk`, and Faugus Launcher as standalone RPM packages, installs the Python/GTK dependencies, and sets up Flatpak (Flathub) with Flatseal and Gear Lever.

### 3. Services, Bootloader & Environment (Phase 3/3)
Installs and configures `virt-manager`/QEMU/libvirt with a default NAT network and imported GUI preferences, locks down firewalld while allowing libvirt traffic, enables `fstrim.timer` and vacuums the journal, zeroes out the `systemd-boot` timeout, configures and enforces Cloudflare DNS, and finally installs and configures Zsh + Oh My Zsh + Powerlevel10k (if Zsh is available), removes the temporary sudo/polkit rule, and prompts the user to reboot.

---

🛠️ How to Run

1. Clone the repository or download the files
```bash
git clone https://github.com/syscore88/opensuse-config.git
```

2. Enter the downloaded folder
```bash
cd opensuse-config
```

3. Make the script executable
```bash
chmod +x install.sh
```

4. Run the script
> ⚠️ **IMPORTANT:** Run the script as a **regular user** (NOT as root/sudo), on a fresh **openSUSE Tumbleweed** installation. It will ask for the administrator password once at the start to configure temporary elevated privileges, and will ask at the end whether to reboot.
```bash
./install.sh
```

---

### ☕ Support the Project

If you find this tool helpful and it saved you some time, consider buying me a coffee to support further development! 

[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://buymeacoffee.com/bartekszczecinski)

---

If you find this project useful, leave a star! ⭐

---

## ⚠️ Requirements & Notes

- A base **openSUSE Tumbleweed** installation with `zypper` and an internet connection (packages come from the default repos, Packman, Games/Emulators/Wine, the Google/Brave repositories, Flathub, and GitHub releases).
- `sudo` access for the current user.
- The script assumes a `systemd-boot` bootloader (`/boot/efi/loader/loader.conf`) — if the file doesn't exist, this step is simply skipped.
- The following optional files, placed alongside `install.sh`, are picked up automatically if present: `.update.sh`, `.local/`, `.config/`.
- The script **removes the default KDE/GNOME mail, PIM, and multimedia apps** (along with their data) and **installs a large number of packages** from several repositories — review the `PACKAGES`/`TO_REMOVE` lists and the `firewalld` rules before running if that doesn't match your needs.
- On failure, check the generated `install_error_<timestamp>.log` file in your home directory for details.
