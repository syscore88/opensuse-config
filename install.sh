#!/bin/bash
# ==========================================================
# KOMPLEKSOWY SKRYPT KONFIGURACYJNY SYSTEMU (OPENSUSE TUMBLEWEED)
# ==========================================================

set -Eeuo pipefail
export ZYPPER_NONINTERACTIVE=1
export ZYPP_LOCK_TIMEOUT=300
export PATH="/usr/sbin:/sbin:$PATH"

detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl* ]]; then
        echo "pl"
    else
        echo "en"
    fi
}
SCRIPT_LANG="$(detect_system_lang)"

INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERR='\033[0;31m'
NC='\033[0m'

TMP_LOG="$(mktemp /tmp/opensuse-install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

cleanup_on_exit() {
    local exit_code=$?
    [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    declare -F restore_packagekit >/dev/null && restore_packagekit || true
    printf '\033[?7h' >&3
    [[ -n "${RPM_DIR:-}" && -d "$RPM_DIR" ]] && rm -rf "$RPM_DIR"
    if [ "$exit_code" -ne 0 ] || [ "${#FAILED_PACKAGES[@]}" -gt 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [ "$exit_code" -ne 0 ]; then
            if [[ "$SCRIPT_LANG" == "pl" ]]; then
                echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
            else
                echo -e "${ERR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
            fi
        fi
    fi
    rm -f "$TMP_LOG"
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
_log_write() { printf "\r\033[K" >&3; echo -e "$1" >&3; echo -e "$1"; }
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${ERR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; _log_write "${WARN}⚠ WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

# ==========================================================
# PACKAGEKIT + BLOKADA ZYPPERA
# ==========================================================
PACKAGEKIT_MASKED=0
PACKAGEKIT_UNITS=(packagekit.service packagekit-offline-update.service)

disable_packagekit() {
    [[ "${PACKAGEKIT_MASKED:-0}" -eq 1 ]] && return 0
    sudo systemctl stop "${PACKAGEKIT_UNITS[@]}" 2>/dev/null || true
    if command -v killall >/dev/null 2>&1; then
        sudo killall -q packagekitd 2>/dev/null || true
    else
        sudo pkill -x packagekitd 2>/dev/null || true
    fi
    sudo systemctl mask "${PACKAGEKIT_UNITS[@]}" 2>/dev/null || true
    PACKAGEKIT_MASKED=1
}

restore_packagekit() {
    [[ "${PACKAGEKIT_MASKED:-0}" -eq 1 ]] || return 0
    sudo systemctl unmask "${PACKAGEKIT_UNITS[@]}" 2>/dev/null || true
    PACKAGEKIT_MASKED=0
}

_zypper_lock_busy() {
    local f
    for f in /run/zypp.pid /var/run/zypp.pid; do
        [[ -e "$f" ]] || continue
        sudo fuser "$f" >/dev/null 2>&1 && return 0
    done
    pgrep -x 'zypper|packagekitd|zypp-refresh' >/dev/null 2>&1 && return 0
    return 1
}

wait_for_zypper_lock() {
    local timeout="${1:-300}" waited=0
    disable_packagekit
    while _zypper_lock_busy; do
        if (( waited >= timeout )); then
            log_warn "Blokada zyppera trwa ponad ${timeout}s - próbuję ją zwolnić." \
                     "zypper lock held for over ${timeout}s - trying to release it."
            sudo killall -q packagekitd 2>/dev/null || sudo pkill -x packagekitd 2>/dev/null || true
            if pgrep -x zypper >/dev/null 2>&1; then
                log_warn "zypper nadal pracuje - nie usuwam pliku blokady, kontynuuję." \
                         "zypper is still running - leaving the lock file alone, continuing."
            else
                sudo rm -f /run/zypp.pid /var/run/zypp.pid 2>/dev/null || true
            fi
            break
        fi
        sleep 3
        waited=$(( waited + 3 ))
    done
}

show_progress() {
    local step=$1
    local total=$2
    local msg=$3
    local percent=$(( step * 100 / total ))

    local cols
    cols=$(tput cols 2>/dev/null)
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    local bar_width=50
    local reserved=12
    if (( cols - reserved < bar_width )); then
        bar_width=$(( cols - reserved ))
        (( bar_width < 10 )) && bar_width=10
    fi

    local overhead=$(( bar_width + reserved ))
    local avail=$(( cols - overhead ))
    if (( avail < 5 )); then avail=5; fi
    if (( ${#msg} > avail )); then
        msg="${msg:0:$((avail - 1))}…"
    fi

    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    local bar_filled=""
    local bar_empty=""
    if [ $filled -gt 0 ]; then printf -v bar_filled '%*s' "$filled" ''; bar_filled="${bar_filled// /#}"; fi
    if [ $empty -gt 0 ]; then printf -v bar_empty '%*s' "$empty" ''; bar_empty="${bar_empty// /-}"; fi

    printf "\r\033[K[\033[1;32m%s\033[0;90m%s\033[0m] %3d%% | \033[1;36m%s\033[0m" "$bar_filled" "$bar_empty" "$percent" "$msg" >&3
}

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    MSG_PHASE_1="[1/4] Przygotowywanie..."
    MSG_PHASE_2="[2/4] Instalacja..."
    MSG_PHASE_3="[3/4] Optymalizacja..."
    MSG_PHASE_4="[4/4] Finalizowanie..."
else
    MSG_PHASE_1="[1/4] Preparing..."
    MSG_PHASE_2="[2/4] Installing..."
    MSG_PHASE_3="[3/4] Optimizing..."
    MSG_PHASE_4="[4/4] Finalizing..."
fi

TOTAL_STEPS=12
FAILED_PACKAGES=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
CURRENT_USER=$(whoami)
RPM_DIR="$(mktemp -d /tmp/rpm_install_XXXXXX)"

if [[ "$EUID" -eq 0 ]]; then
    echo -e "${ERR}✘ Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z uprawnieniami sudo.${NC}" >&3
    exit 1
fi

printf '\033[?7h\n' >&3

if [[ -z "$CURRENT_USER" ]]; then
    echo -e "${ERR}✘ Nie udało się ustalić bieżącego użytkownika (whoami zwróciło pusty ciąg).${NC}" >&3
    exit 1
fi

RUN0_NOPASSWD_FILE="/etc/polkit-1/rules.d/51-run0-nopasswd.rules"
SUDOERS_NOPASSWD_FILE="/etc/sudoers.d/99-temp-installer"
USE_RUN0=0
if sudo --version 2>/dev/null | grep -qi "run0"; then
    USE_RUN0=1
fi

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    printf 'Wymagane hasło sudo:\n' >&3
else
    printf 'sudo password required:\n' >&3
fi
sudo -v

( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!

if command -v visudo >/dev/null 2>&1; then
    SUDOERS_TMP="$(mktemp)"
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$CURRENT_USER" > "$SUDOERS_TMP"
    if sudo visudo -cf "$SUDOERS_TMP" &>/dev/null; then
        sudo install -m 0440 -o root -g root "$SUDOERS_TMP" "$SUDOERS_NOPASSWD_FILE" 2>/dev/null || true
    fi
    rm -f "$SUDOERS_TMP"
fi

if [[ "$USE_RUN0" -eq 1 ]] || [[ ! -f "$SUDOERS_NOPASSWD_FILE" ]]; then
    printf 'polkit.addRule(function(action, subject) {\n    if (subject.user == "%s") {\n        return polkit.Result.YES;\n    }\n});\n' "$CURRENT_USER" | sudo tee "$RUN0_NOPASSWD_FILE" > /dev/null
    sudo systemctl try-restart polkit 2>/dev/null || true
    USE_RUN0=1
fi

printf '\033[?7l' >&3

# ==========================================================
#  ETAP 1/4: PRZYGOTOWYWANIE
# ==========================================================
show_progress 0 $TOTAL_STEPS "$MSG_PHASE_1"

if [[ -f "$SCRIPT_DIR/.update.sh" ]]; then
    cp -af "$SCRIPT_DIR/.update.sh" ~/.update.sh
    chmod +x ~/.update.sh
fi

if [[ -d "$SCRIPT_DIR/.local" ]]; then
    mkdir -p ~/.local
    cp -afT "$SCRIPT_DIR/.local" ~/.local
fi

if [[ -d "$SCRIPT_DIR/.config" ]]; then
    mkdir -p ~/.config
    cp -afT "$SCRIPT_DIR/.config" ~/.config
fi

show_progress 1 $TOTAL_STEPS "$MSG_PHASE_1"

sudo systemctl stop packagekit.service packagekit-offline-update.service 2>/dev/null || true
sudo systemctl mask packagekit.service packagekit-offline-update.service 2>/dev/null || true
sudo killall -9 packagekitd 2>/dev/null || true

wait_for_zypper_lock() {
    local i=0
    while pgrep -x zypper >/dev/null || pgrep -x packagekitd >/dev/null; do
        if (( i++ >= 24 )); then
            sudo systemctl stop packagekit.service 2>/dev/null || true
            sudo killall -9 zypper packagekitd 2>/dev/null || true
            sudo rm -f /var/run/zypp.pid 2>/dev/null || true
            break
        fi
        sleep 5
    done
}
disable_packagekit

wait_for_zypper_lock
for pkg in curl wget pciutils gpg2 dconf; do
    sudo zypper install -y "$pkg" || true
done

show_progress 2 $TOTAL_STEPS "$MSG_PHASE_1"

wait_for_zypper_lock
sudo zypper addrepo -cfp 90 https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/ packman || true
sudo rpm --import https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/repodata/repomd.xml.key 2>/dev/null || true

sudo zypper addrepo -cfp 80 https://download.opensuse.org/repositories/games/openSUSE_Tumbleweed/ games || true
sudo zypper addrepo -cfp 80 https://download.opensuse.org/repositories/Emulators/openSUSE_Tumbleweed/ emulators || true
sudo zypper addrepo -cfp 80 https://download.opensuse.org/repositories/Emulators:/Wine/openSUSE_Tumbleweed/ emulators-wine || true

sudo zypper addrepo -cfp 80 https://dl.google.com/linux/chrome/rpm/stable/x86_64 google-chrome || true
sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null || true

BRAVE_KEY_ID="0686B78420038257"
if ! sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc 2>/dev/null; then
    BRAVE_GNUPGHOME="$(mktemp -d)"
    KEY_FETCHED=true
    if ! gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keyserver.ubuntu.com --recv-keys "$BRAVE_KEY_ID" 2>/dev/null; then
        if ! gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keys.openpgp.org --recv-keys "$BRAVE_KEY_ID" 2>/dev/null; then
            KEY_FETCHED=false
        fi
    fi
    if [ "$KEY_FETCHED" = true ]; then
        gpg --homedir "$BRAVE_GNUPGHOME" --armor --export "$BRAVE_KEY_ID" > "$BRAVE_GNUPGHOME/brave-core.asc" 2>/dev/null || true
        sudo rpm --import "$BRAVE_GNUPGHOME/brave-core.asc" 2>/dev/null || true
    fi
    rm -rf "$BRAVE_GNUPGHOME"
fi

sudo zypper addrepo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo || true

wait_for_zypper_lock
sudo zypper --gpg-auto-import-keys refresh || true
wait_for_zypper_lock
sudo zypper dup -y --allow-vendor-change || true

sudo mkdir -p /etc/NetworkManager/conf.d
echo -e "[main]\ndns=default\nrc-manager=symlink" | sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null
echo -e "[global-dns]\n\n[global-dns-domain-*]\nservers=1.1.1.1,1.0.0.1,2606:4700:4700::1112,2606:4700:4700::1002" | sudo tee /etc/NetworkManager/conf.d/global-dns.conf > /dev/null

ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -v "^lo" | head -n 1 | cut -d: -f1 || true)
if [[ -n "$ACTIVE_CONN" ]]; then
    sudo nmcli connection modify "$ACTIVE_CONN" ipv4.dns "1.1.1.1,1.0.0.1" ipv6.dns "2606:4700:4700::1112,2606:4700:4700::1002"
    sudo nmcli connection up "$ACTIVE_CONN" || true
fi

show_progress 3 $TOTAL_STEPS "$MSG_PHASE_1"

TO_REMOVE=(
    opensuse-welcome-launcher plasma-welcome dragonplayer elisa
    nano konqueror plasma-browser-integration plasma-vault
    plasma-thunderbolt kontact kmail kontrast krdp krfb cosmic-player
    kaddressbook kdepim-runtime akonadi-server akregator
    epiphany decibels korganizer kwalletmanager rhythmbox showtime
    gnome-calendar gnome-clocks gnome-user-docs gnome-contacts
    gnome-maps gnome-weather yelp evolution evolution-common
    evolution-plugins evolution-ews parole gnome-music
)
wait_for_zypper_lock
for pkg in "${TO_REMOVE[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
        sudo zypper remove -y "$pkg" 2>/dev/null || true
    fi
done
wait_for_zypper_lock
sudo zypper autoremove -y 2>/dev/null || true

rm -rf ~/.local/share/akonadi ~/.local/share/kmail2 ~/.local/share/local-mail ~/.local/share/contacts ~/.local/share/korganizer ~/.local/share/akregator ~/.local/share/kontact ~/.local/share/konqueror
rm -rf ~/.config/akonadi* ~/.config/kmail* ~/.config/kontact* ~/.config/korganizer* ~/.config/kaddressbook* ~/.config/akregator* ~/.config/emailidentities ~/.config/mailtransports
rm -rf ~/.cache/akonadi* ~/.cache/kmail* ~/.cache/kontact* ~/.cache/korganizer* ~/.cache/kaddressbook* ~/.cache/akregator* ~/.cache/konqueror*
rm -rf ~/.local/share/{epiphany,decibels,gnome-user-docs,gnome-contacts,gnome-maps,gnome-weather,evolution,gnome-music,parole,rhythmbox,showtime,epiphany,decibels,dragonplayer,elisa,cosmic-player}
rm -rf ~/.config/{epiphany,decibels,gnome-user-docs,gnome-contacts,gnome-maps,gnome-weather,evolution,gnome-music,parole,rhythmbox,showtime,epiphany,decibels,dragonplayer,elisa,cosmic-player}
rm -rf ~/.cache/{epiphany,decibels,gnome-user-docs,gnome-contacts,gnome-maps,gnome-weather,evolution,gnome-music,parole,rhythmbox,showtime,epiphany,decibels,dragonplayer,elisa,cosmic-player}

if rpm -q plasma-desktop &>/dev/null || rpm -q plasma-workspace &>/dev/null; then
    mkdir -p ~/.config
    cat > ~/.config/kwalletrc << 'EOF'
[Wallet]
Close When Idle=false
Close on Screensaver=false
Default Wallet=kdewallet
Enabled=false
First Use=false
Idle Timeout=10
Launch Manager=false
Leave Manager Open=false
Leave Open=true
Prompt on Open=false
Use One Wallet=true

[org.freedesktop.secrets]
apiEnabled=false
EOF
fi

# ==========================================================
#  ETAP 2/4: INSTALACJA
# ==========================================================
show_progress 4 $TOTAL_STEPS "$MSG_PHASE_2"

wait_for_zypper_lock
sudo zypper install -y google-chrome-stable || true
sudo zypper install -y brave-origin || true

PACKAGES=(
    dconf-editor fastfetch unrar git mc android-tools pv zenity innoextract
    audacity gimp gmic mixxx kdenlive kolourpaint soundconverter handbrake-gtk
    telegram-desktop qbittorrent zsh qt6-declarative-devel qt6-base-devel
    bleachbit makeself vim cdemu-daemon cdemu-client vlc vlc-codecs
    gamemode gamescope mangohud libvkd3d1 wine-staging wine-mono wine-gecko
    cmake meson patterns-devel-base-devel_basis kernel-devel
    gstreamer-plugins-ugly qmmp ninja pkgconf-pkg-config vulkan-devel
   )

wait_for_zypper_lock
sudo zypper --gpg-auto-import-keys refresh --force || true

for pkg in "${PACKAGES[@]}"; do
    wait_for_zypper_lock
    if sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null; then
        continue
    fi
    sudo zypper install -y --allow-vendor-change --from packman "$pkg" 2>/dev/null || FAILED_PACKAGES+=("$pkg")
done

sudo systemctl disable --now cdemu-daemon 2>/dev/null || true
sudo systemctl mask cdemu-daemon 2>/dev/null || true
mkdir -p "$HOME/.config/autostart"
for f in /etc/xdg/autostart/gcdemu.desktop /etc/xdg/autostart/cdemu.desktop /usr/share/applications/gcdemu.desktop; do
    if [[ -f "$f" ]]; then
        cp -f "$f" "$HOME/.config/autostart/$(basename "$f")"
        if grep -q '^Hidden=' "$HOME/.config/autostart/$(basename "$f")"; then
            sed -i 's/^Hidden=.*/Hidden=true/' "$HOME/.config/autostart/$(basename "$f")"
        else
            echo "Hidden=true" >> "$HOME/.config/autostart/$(basename "$f")"
        fi
    fi
done
pkill -f gcdemu 2>/dev/null || true

show_progress 5 $TOTAL_STEPS "$MSG_PHASE_2"

PACKAGES_32=(
    mangohud-32bit libgamemodeauto0-32bit libvkd3d1-32bit wine-staging-32bit
    libopenal1-32bit libXdamage1-32bit libXtst6-32bit
    libgtk-2_0-0-32bit libgtk-3-0-32bit
)

GPU_VENDOR=$(lspci -nn | grep -iE "VGA|3D|Display" || true)
DRACUT_CONF="/etc/dracut.conf.d/90-gpu.conf"
MESA_32_PKGS=(Mesa-libGL1-32bit Mesa-dri-32bit libvulkan1-32bit)

GPU_HAS_NVIDIA=0
GPU_HAS_AMD=0
GPU_HAS_INTEL=0
echo "$GPU_VENDOR" | grep -iq "nvidia" && GPU_HAS_NVIDIA=1
echo "$GPU_VENDOR" | grep -iqE "amd|radeon" && GPU_HAS_AMD=1
echo "$GPU_VENDOR" | grep -iq "intel" && GPU_HAS_INTEL=1

GPU_VENDOR_COUNT=$(( GPU_HAS_NVIDIA + GPU_HAS_AMD + GPU_HAS_INTEL ))
FORCE_DRIVERS=""

if (( GPU_VENDOR_COUNT >= 2 )); then
    log_info "Wykryto hybrydowy układ graficzny (więcej niż jedno GPU)." "Detected a hybrid GPU setup (more than one GPU)."
fi

if (( GPU_HAS_NVIDIA )); then
    PACKAGES_32+=(libglvnd-32bit)
    FORCE_DRIVERS+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm"
fi
if (( GPU_HAS_AMD )); then
    PACKAGES_32+=(libvulkan_radeon-32bit)
    FORCE_DRIVERS+=" amdgpu"
fi
if (( GPU_HAS_INTEL )); then
    PACKAGES_32+=(libvulkan_intel-32bit)
    FORCE_DRIVERS+=" i915"
fi

if (( GPU_VENDOR_COUNT > 0 )); then
    readarray -t PACKAGES_32 < <(printf '%s\n' "${PACKAGES_32[@]}" | awk '!seen[$0]++')
    echo "force_drivers+=\"${FORCE_DRIVERS} \"" | sudo tee "$DRACUT_CONF" > /dev/null
else
    PACKAGES_32+=("${MESA_32_PKGS[@]}")
    sudo rm -f "$DRACUT_CONF"
fi

for pkg in "${PACKAGES_32[@]}"; do
    wait_for_zypper_lock
    sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null || FAILED_PACKAGES+=("$pkg")
done

if [[ -f "$DRACUT_CONF" ]]; then
    sudo dracut --force || true
fi

show_progress 6 $TOTAL_STEPS "$MSG_PHASE_2"

download_rpm() {
    local name="$1" url="$2" dest="$3"
    wget -q --timeout=30 -O "$dest" "$url" || { rm -f "$dest"; FAILED_PACKAGES+=("$name"); }
}

install_discord_rpm() {
    local dest="$RPM_DIR/discord.rpm"
    if wget -q --user-agent="Mozilla/5.0" "https://discord.com/api/download?platform=linux&format=rpm" -O "$dest"; then
        if file "$dest" | grep -q "RPM"; then
            wait_for_zypper_lock
            sudo zypper install -y --allow-unsigned-rpm "$dest" 2>/dev/null || true
        fi
        rm -f "$dest"
    fi
}

wait_for_zypper_lock
if sudo zypper repos 2>/dev/null | grep -iq "packman"; then
    sudo zypper install -y discord 2>/dev/null || install_discord_rpm
else
    install_discord_rpm
fi

OPENCODE_URL=$(curl -sfL https://api.github.com/repos/anomalyco/opencode/releases/latest | grep "browser_download_url.*opencode-desktop-linux-x86_64\.rpm" | cut -d '"' -f 4 || true)
[[ -n "$OPENCODE_URL" ]] && download_rpm "opencode-desktop" "$OPENCODE_URL" "$RPM_DIR/opencode-desktop.rpm"

FAUGUS_URL=$(curl -sf https://api.github.com/repos/Faugus/faugus-launcher/releases/latest \
    | grep "browser_download_url.*x86_64.rpm" | cut -d '"' -f 4 || true)

if [[ -n "$FAUGUS_URL" ]]; then
    FAUGUS_RPM="$RPM_DIR/faugus-launcher.rpm"
    download_rpm "faugus" "$FAUGUS_URL" "$FAUGUS_RPM"
    if [[ -f "$FAUGUS_RPM" ]]; then
        wait_for_zypper_lock
        sudo rpm -Uvh --nodeps --force "$FAUGUS_RPM" 2>/dev/null || true
        rm -f "$FAUGUS_RPM"
    fi
fi

shopt -s nullglob
RPM_FILES=("$RPM_DIR"/*.rpm)
if [[ ${#RPM_FILES[@]} -gt 0 ]]; then
    wait_for_zypper_lock
    sudo zypper install -y --allow-unsigned-rpm "${RPM_FILES[@]}" 2>/dev/null || true
fi
shopt -u nullglob
rm -rf "$RPM_DIR"

LSFG_TMP="$(mktemp -d)"
LSFG_URL="$(curl -fsSL https://builds.lsfg-vk.dev/ | grep -oE 'https://[^"'"'"']+linux[^"'"'"']*\.tar\.xz' | head -n1 || true)"
if [[ -n "$LSFG_URL" ]] && curl -fsSL -o "$LSFG_TMP/lsfg-vk.tar.xz" "$LSFG_URL"; then
    mkdir -p "$HOME/.local"
    tar -xf "$LSFG_TMP/lsfg-vk.tar.xz" -C "$HOME/.local" || true
fi
rm -rf "$LSFG_TMP"

show_progress 7 $TOTAL_STEPS "$MSG_PHASE_2"

pkg_available() {
    wait_for_zypper_lock
    sudo zypper --non-interactive install --dry-run "$1" &>/dev/null
}

QEMU_PKG=""
for candidate in qemu-kvm qemu-x86 qemu; do
    if pkg_available "$candidate"; then
        QEMU_PKG="$candidate"
        break
    fi
done
[[ -z "$QEMU_PKG" ]] && QEMU_PKG="qemu-x86"

OVMF_PKG=""
for candidate in qemu-ovmf-x86_64 ovmf edk2-ovmf; do
    if pkg_available "$candidate"; then
        OVMF_PKG="$candidate"
        break
    fi
done

VIRT_PACKAGES=(virt-manager "$QEMU_PKG" qemu-tools libvirt libvirt-daemon-qemu)
[[ -n "$OVMF_PKG" ]] && VIRT_PACKAGES+=("$OVMF_PKG")

wait_for_zypper_lock
sudo zypper install -y --allow-vendor-change "${VIRT_PACKAGES[@]}" 2>/dev/null || true

if command -v dconf &>/dev/null; then
    dconf load /org/virt-manager/virt-manager/ <<'DCONFEOF'
[/]
manager-window-height=297
manager-window-width=478
xmleditor-enabled=true

[confirm]
delete-storage=false
forcepoweroff=false

[connections]
autoconnect=['qemu:///system']
uris=['qemu:///system']

[conns/qemu:system]
window-size=(800, 600)

[details]
show-toolbar=true

[new-vm]
cpu-default='host-passthrough'
firmware='uefi'
graphics-type='spice'
storage-format='raw'

[stats]
enable-disk-poll=true
enable-memory-poll=true
enable-net-poll=true

[vmlist-fields]
disk-usage=false
network-traffic=false

[vms/2a91721fef6c4249997ea19b01801825]
autoconnect=1
vm-window-size=(1280, 842)
DCONFEOF
fi

for svc in libvirtd virtqemud; do
    if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        sudo systemctl enable --now "${svc}.service" 2>/dev/null || true
        break
    fi
done

if ! sudo virsh net-info default &>/dev/null; then
    sudo virsh net-define /usr/share/libvirt/networks/default.xml 2>/dev/null || true
fi
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default 2>/dev/null || true

if command -v firewall-cmd &>/dev/null; then
    sudo systemctl enable --now firewalld 2>/dev/null || true
    sudo firewall-cmd --permanent --zone=libvirt --add-interface=virbr0 2>/dev/null || true
    sudo firewall-cmd --permanent --add-source=192.168.122.0/24 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
fi

for grp in libvirt kvm; do
    if getent group "$grp" &>/dev/null; then
        sudo usermod -aG "$grp" "$CURRENT_USER" 2>/dev/null || true
    fi
done

show_progress 8 $TOTAL_STEPS "$MSG_PHASE_2"

wait_for_zypper_lock
sudo zypper install -y flatpak 2>/dev/null || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
flatpak update --appstream 2>/dev/null || true

flatpak install --user -y flathub com.github.tchx84.Flatseal 2>/dev/null || true
flatpak install --user -y flathub it.mijorus.gearlever 2>/dev/null || true

# ==========================================================
#  ETAP 3/4: OPTYMALIZACJA
# ==========================================================
show_progress 9 $TOTAL_STEPS "$MSG_PHASE_3"

sudo systemctl unmask packagekit.service packagekit-offline-update.service 2>/dev/null || true
restore_packagekit
sudo systemctl enable fstrim.timer || true
sudo journalctl --vacuum-time=2d || true

show_progress 10 $TOTAL_STEPS "$MSG_PHASE_3"

LOADER_CONF="/boot/efi/loader/loader.conf"
if sudo test -f "$LOADER_CONF"; then
    if sudo grep -q "^#\?timeout" "$LOADER_CONF"; then
        sudo sed -i -E 's/^#?[[:space:]]*timeout[[:space:]].*/timeout 0/' "$LOADER_CONF"
    else
        echo "timeout 0" | sudo tee -a "$LOADER_CONF" > /dev/null
    fi
    if command -v bootctl >/dev/null 2>&1; then
        sudo bootctl set-timeout 0 || true
    fi
fi

show_progress 11 $TOTAL_STEPS "$MSG_PHASE_3"

ZSH_BIN=$(command -v zsh || true)

if [[ -n "$ZSH_BIN" ]]; then
    sudo chsh -s "$ZSH_BIN" "$CURRENT_USER" || true
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
    fi

    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$P10K_DIR" ]]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" || true
    fi

    ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    AUTOSUGGESTIONS_DIR="$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
    if [[ ! -d "$AUTOSUGGESTIONS_DIR" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$AUTOSUGGESTIONS_DIR" || true
    fi
    SYNTAX_HIGHLIGHT_DIR="$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
    if [[ ! -d "$SYNTAX_HIGHLIGHT_DIR" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_HIGHLIGHT_DIR" || true
    fi

    ZSHRC="$HOME/.zshrc"
    if [[ -f "$ZSHRC" ]]; then
        sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC" || true
        sed -i 's/^plugins=(.*/plugins=(git sudo systemd suse zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC" || true
        SHELL_LOCALE="${LANG:-${LC_ALL:-${LC_MESSAGES:-en_US.UTF-8}}}"
        if command -v locale &>/dev/null; then
            AVAILABLE_LOCALES="$(locale -a 2>/dev/null)"
            if ! echo "$AVAILABLE_LOCALES" | grep -qiF "$SHELL_LOCALE" && ! echo "$AVAILABLE_LOCALES" | grep -qiF "$(echo "$SHELL_LOCALE" | sed 's/UTF-8/utf8/')"; then
                SHELL_LOCALE="en_US.UTF-8"
            fi
        fi
        grep -q "^export LC_ALL=" "$ZSHRC" || echo "export LC_ALL=${SHELL_LOCALE}" >> "$ZSHRC"
        grep -q "^fastfetch"          "$ZSHRC" || echo "fastfetch"                  >> "$ZSHRC"
    fi
fi

[[ -f "$RUN0_NOPASSWD_FILE" ]] && sudo rm -f "$RUN0_NOPASSWD_FILE"
[[ "$USE_RUN0" -eq 1 ]] && sudo systemctl try-restart polkit 2>/dev/null || true
sudo rm -f "$SUDOERS_NOPASSWD_FILE"
[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true

# =============================================================
#  ETAP 4/4: CZYSZCZENIE
# =============================================================
show_progress 12 $TOTAL_STEPS "$MSG_PHASE_4"
echo -e "\n" >&3

if [ "${#FAILED_PACKAGES[@]}" -gt 0 ]; then
    log_warn "Nie udało się zainstalować: ${FAILED_PACKAGES[*]}" "Failed to install: ${FAILED_PACKAGES[*]}"
fi

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}✔ CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

# ==========================================================
#  RESTART SYSTEMU
# ==========================================================
if [[ "$SCRIPT_LANG" == "pl" ]]; then
    RESTART_PROMPT="Czy chcesz teraz zrestartować system? [T/N]: "
else
    RESTART_PROMPT="Do you want to restart the system now? [Y/N]: "
fi
echo -en "${INFO}==> ${RESTART_PROMPT}${NC}" >&3
read -r RESTART_CHOICE < /dev/tty
case "$RESTART_CHOICE" in
    [YyTt]*)
        systemctl reboot
        ;;
    *)
        exit 0
        ;;
esac
