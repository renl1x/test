#!/bin/bash
set -euo pipefail

STATE_DIR="/tmp/debian_install_state"
mkdir -p "$STATE_DIR"

if command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; BOLD=''; NC=''
fi

confirm() {
    local prompt="$1"
    local resposta
    read -p "$prompt (s/n): " -n 1 resposta
    echo
    if [[ -z "$resposta" ]]; then
        return 0
    else
        [[ "$resposta" =~ ^[Ss]$ ]]
    fi
}

clear_screen() { clear; }

show_section() {
    echo "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
    echo "${GREEN}► $1${NC}"
    echo "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

show_option() {
    local num="$1"
    local desc="$2"
    echo "  ${CYAN}$num${NC}) $desc"
}

detect_gpu() {
    local gpu_info=$(lspci -nn 2>/dev/null | grep -E "VGA|3D|Display" | head -1)
    if echo "$gpu_info" | grep -qi "nvidia"; then
        echo "nvidia" > "$STATE_DIR/gpu_driver"
    elif echo "$gpu_info" | grep -qi "amd\|radeon"; then
        echo "amd" > "$STATE_DIR/gpu_driver"
    elif echo "$gpu_info" | grep -qi "intel"; then
        echo "intel" > "$STATE_DIR/gpu_driver"
    else
        echo "nvidia" > "$STATE_DIR/gpu_driver"
    fi
}

detect_cpu() {
    local cpu_info=$(cat /proc/cpuinfo 2>/dev/null)
    if echo "$cpu_info" | grep -qi "intel"; then
        echo "intel" > "$STATE_DIR/cpu"
    elif echo "$cpu_info" | grep -qi "amd"; then
        echo "amd" > "$STATE_DIR/cpu"
    else
        echo "intel" > "$STATE_DIR/cpu"
    fi
}

setup_sources() {
    if [ -f /etc/apt/sources.list ]; then
        sudo sed -i 's/\(main\)/\1 contrib non-free/g' /etc/apt/sources.list
    fi
    
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        sudo sed -i '/^Components:/ s/\(main\)/\1 contrib non-free/' /etc/apt/sources.list.d/debian.sources
    fi
    
    sudo apt update
}

install_base() {
    sudo apt install -y earlyoom podman neovim ufw gamemode fastfetch chrony
    sudo systemctl enable ufw
    sudo systemctl enable earlyoom
    sudo systemctl enable chrony
    sudo systemctl start chrony
}

setup_package_managers() {
    local desktop=$(cat "$STATE_DIR/desktop")
    
    sudo apt install -y flatpak snapd
    
    if [[ "$desktop" == "gnome" ]]; then
        sudo apt install -y gnome-software-plugin-flatpak gnome-software-plugin-snap
    elif [[ "$desktop" == "kde" ]]; then
        sudo apt install -y plasma-discover-backend-flatpak plasma-discover-backend-snap
    fi
    
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo systemctl enable snapd
    sudo systemctl start snapd
}

setup_zram() {
    sudo apt install -y systemd-zram-generator
    sudo tee /etc/systemd/zram-generator.conf > /dev/null <<EOF
[zram0]
zram-size = ram * 0.25
compression-algorithm = zstd
swap-priority = 100
EOF
    sudo systemctl daemon-reload
    sudo systemctl start systemd-zram-setup@zram0.service
}

setup_btrfs_compression() {
    if mount | grep -q "btrfs"; then
        sudo sed -i '/btrfs.*compress,/s/compress,/compress=zstd,/g' /etc/fstab
        sudo sed -i '/btrfs.*compress[^=]/s/compress/compress=zstd/g' /etc/fstab
        sudo sed -i '/btrfs.*compress=zlib/s/compress=zlib/compress=zstd/g' /etc/fstab
        sudo mount -o remount /
        echo "${GREEN}Compressão BTRFS configurada para zstd${NC}"
    fi
}

import_mok_key() {
    if ! command -v mokutil &>/dev/null; then
        echo "${YELLOW}mokutil não instalado. Pulando importação da chave MOK.${NC}"
        return
    fi
    
    if ! sudo mokutil --sb-state 2>/dev/null | grep -qi "SecureBoot enabled"; then
        echo "${YELLOW}Secure Boot não está ativo. Pulando importação da chave MOK.${NC}"
        return
    fi
    
    if [ ! -f /var/lib/dkms/mok.pub ]; then
        echo "${YELLOW}Arquivo /var/lib/dkms/mok.pub não encontrado. Pulando importação da chave MOK.${NC}"
        return
    fi
    
    if sudo mokutil --list-enrolled 2>/dev/null | grep -q "Debian Secure Boot"; then
        echo "${GREEN}Chave MOK já está enrollada no sistema. Pulando importação.${NC}"
        return
    fi
    
    echo "${YELLOW}Importando chave MOK para Secure Boot...${NC}"
    echo "${YELLOW}Digite uma senha (8-16 caracteres) quando solicitado.${NC}"
    sudo mokutil --import /var/lib/dkms/mok.pub
    echo "${GREEN}Chave MOK importada com sucesso!${NC}"
    echo "${YELLOW}Reinicie o sistema para concluir o enrollment da chave MOK.${NC}"
}

install_gpu_drivers() {
    local gpu=$(cat "$STATE_DIR/gpu_driver")
    
    case "$gpu" in
        "intel"|"amd")
            sudo apt install -y mesa-vulkan-drivers
            ;;
        "nvidia")
            sudo apt install -y linux-headers-amd64
            wget https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb
            sudo dpkg -i cuda-keyring_1.1-1_all.deb
            sudo apt update
            sudo apt -y install nvidia-open
            rm -f cuda-keyring_1.1-1_all.deb
            import_mok_key
            ;;
    esac
}

install_cpu_microcode() {
    local cpu=$(cat "$STATE_DIR/cpu")
    
    case "$cpu" in
        "intel")
            sudo apt install -y intel-microcode
            ;;
        "amd")
            sudo apt install -y amd64-microcode
            ;;
    esac
}

select_desktop() {
    clear_screen
    show_section "AMBIENTE DESKTOP / DESKTOP ENVIRONMENT"
    show_option "1" "GNOME"
    show_option "2" "KDE Plasma"
    show_option "3" "Nenhum"
    echo ""
    read -p "Opção [1-3] (Enter para GNOME): " de_opt
    case "$de_opt" in
        1|"") echo "gnome" > "$STATE_DIR/desktop"
             echo "${GREEN}Desktop: GNOME${NC}" ;;
        2) echo "kde" > "$STATE_DIR/desktop"
           echo "${GREEN}Desktop: KDE Plasma${NC}" ;;
        3) echo "none" > "$STATE_DIR/desktop"
           echo "${GREEN}Desktop: Nenhum${NC}" ;;
        *) echo "${RED}Opção inválida.${NC}"
           sleep 1
           select_desktop
           return
    esac
    sleep 2
}

install_desktop() {
    local desktop=$(cat "$STATE_DIR/desktop")
    
    case "$desktop" in
        "gnome")
            sudo apt install -y gdm3 gnome-initial-setup gnome-console gnome-software gnome-tweaks gnome-disk-utility gnome-backgrounds
            sudo systemctl enable gdm3
            ;;
        "kde")
            sudo apt install -y sddm plasma-desktop plasma-workspace-wallpapers konsole dolphin discover kdeconnect partitionmanager ark
            sudo systemctl enable sddm
            ;;
        "none")
            echo "${YELLOW}Nenhum desktop instalado.${NC}"
            ;;
    esac
}

setup_network() {
    sudo sed -i '/^allow-hotplug /s/^/#/' /etc/network/interfaces
    sudo sed -i '/^iface .* inet /s/^/#/' /etc/network/interfaces
    sudo sed -i '/^iface .* inet6 /s/^/#/' /etc/network/interfaces
}

setup_performance_vars() {
    sudo mkdir -p /etc/environment.d
    sudo tee /etc/environment.d/performance.conf > /dev/null <<EOF
MESA_SHADER_CACHE_MAX_SIZE=12G
__GL_SHADER_DISK_CACHE_SIZE=12000000000
EOF
}

remove_packages() {
    sudo apt remove -y nano wget vim-common
    sudo apt autoremove -y
}

ask_reboot() {
    echo ""
    echo "${GREEN}Instalação concluída com sucesso!${NC}"
    echo "${YELLOW}Recomenda-se reiniciar o sistema para aplicar todas as configurações.${NC}"
    if confirm "Deseja reiniciar agora?"; then
        echo "${GREEN}Reiniciando o sistema...${NC}"
        sudo reboot
    else
        echo "${YELLOW}Lembre-se de reiniciar o sistema posteriormente para aplicar todas as configurações.${NC}"
    fi
}

main() {
    sudo apt update
    detect_gpu
    detect_cpu
    select_desktop
    setup_sources
    install_base
    install_cpu_microcode
    install_gpu_drivers
    install_desktop
    setup_network
    setup_zram
    setup_btrfs_compression
    setup_package_managers
    setup_performance_vars
    remove_packages
    ask_reboot
}

main
