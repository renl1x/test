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

detect_distro() {
    if [ -f /etc/debian_version ]; then
        echo "debian" > "$STATE_DIR/distro"
    elif [ -f /etc/arch-release ]; then
        echo "arch" > "$STATE_DIR/distro"
    else
        echo "unknown" > "$STATE_DIR/distro"
    fi
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
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "debian" ]]; then
        if [ -f /etc/apt/sources.list ]; then
            sudo sed -i 's/\(main\)/\1 contrib non-free/g' /etc/apt/sources.list
        fi
        
        if [ -f /etc/apt/sources.list.d/debian.sources ]; then
            sudo sed -i '/^Components:/ s/\(main\)/\1 contrib non-free/' /etc/apt/sources.list.d/debian.sources
        fi
        
        sudo apt update
        sudo apt upgrade -y
    elif [[ "$distro" == "arch" ]]; then
        sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
        sudo pacman-key --lsign-key 3056513887B78AEB
        sudo pacman -U --noconfirm \
            "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst" \
            "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"
        sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
        sudo sed -i '/Color/a ILoveCandy' /etc/pacman.conf
        sudo sed -i '/^ParallelDownloads/d' /etc/pacman.conf
        sudo sed -i '/ILoveCandy/a ParallelDownloads = 15' /etc/pacman.conf
        echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
        sudo pacman -Syu --noconfirm
    fi
}

install_base() {
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "debian" ]]; then
        sudo apt install -y podman neovim ufw gamemode fastfetch chrony
        sudo systemctl enable ufw
        sudo systemctl enable chrony
        sudo systemctl start chrony
    elif [[ "$distro" == "arch" ]]; then
        sudo pacman -S --noconfirm apparmor podman fastfetch gamemode yay topgrade fwupd
        sudo systemctl enable apparmor
        sudo systemctl start apparmor
        sudo systemctl enable fwupd
        sudo systemctl start fwupd
    fi
}

setup_package_managers() {
    local desktop=$(cat "$STATE_DIR/desktop")
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "debian" ]]; then
        sudo apt install -y flatpak
        
        if [[ "$desktop" == "gnome" ]]; then
            sudo apt install -y gnome-software-plugin-flatpak
        elif [[ "$desktop" == "kde" ]]; then
            sudo apt install -y plasma-discover-backend-flatpak
        fi
        
        sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    elif [[ "$distro" == "arch" ]]; then
        sudo pacman -S --noconfirm flatpak
    fi
}

setup_zram() {
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "debian" ]]; then
        sudo apt install -y systemd-zram-generator
        sudo tee /etc/systemd/zram-generator.conf > /dev/null <<EOF
[zram0]
zram-size = ram * 0.25
compression-algorithm = zstd
swap-priority = 100
EOF
        sudo systemctl daemon-reload
        sudo systemctl start systemd-zram-setup@zram0.service
    fi
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
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "debian" ]]; then
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
    elif [[ "$distro" == "arch" ]]; then
        case "$gpu" in
            "intel")
                sudo pacman -S --noconfirm vulkan-intel
                ;;
            "amd")
                sudo pacman -S --noconfirm vulkan-radeon
                ;;
            "nvidia")
                sudo pacman -S --noconfirm nvidia-open
                ;;
        esac
    fi
}

install_cpu_microcode() {
    local cpu=$(cat "$STATE_DIR/cpu")
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "debian" ]]; then
        case "$cpu" in
            "intel")
                sudo apt install -y intel-microcode
                ;;
            "amd")
                sudo apt install -y amd64-microcode
                ;;
        esac
    elif [[ "$distro" == "arch" ]]; then
        case "$cpu" in
            "intel")
                sudo pacman -S --noconfirm intel-ucode
                ;;
            "amd")
                sudo pacman -S --noconfirm amd-ucode
                ;;
        esac
    fi
}

select_desktop() {
    clear_screen
    show_section "AMBIENTE DESKTOP / DESKTOP ENVIRONMENT"
    show_option "1" "GNOME"
    show_option "2" "KDE Plasma"
    show_option "3" "Nenhum"
    
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "arch" ]]; then
        show_option "4" "COSMIC"
        show_option "5" "Dank Linux"
    fi
    
    echo ""
    read -p "Opção [1-3] (Enter para GNOME): " de_opt
    
    case "$de_opt" in
        1|"") echo "gnome" > "$STATE_DIR/desktop"
             echo "${GREEN}Desktop: GNOME${NC}" ;;
        2) echo "kde" > "$STATE_DIR/desktop"
           echo "${GREEN}Desktop: KDE Plasma${NC}" ;;
        3) echo "none" > "$STATE_DIR/desktop"
           echo "${GREEN}Desktop: Nenhum${NC}" ;;
        4) 
            if [[ "$distro" == "arch" ]]; then
                echo "cosmic" > "$STATE_DIR/desktop"
                echo "${GREEN}Desktop: COSMIC${NC}"
            else
                echo "${RED}Opção inválida.${NC}"
                sleep 1
                select_desktop
                return
            fi
            ;;
        5)
            if [[ "$distro" == "arch" ]]; then
                echo "dank" > "$STATE_DIR/desktop"
                echo "${GREEN}Desktop: Dank Linux${NC}"
            else
                echo "${RED}Opção inválida.${NC}"
                sleep 1
                select_desktop
                return
            fi
            ;;
        *) echo "${RED}Opção inválida.${NC}"
           sleep 1
           select_desktop
           return
    esac
    sleep 2
}

install_desktop() {
    local desktop=$(cat "$STATE_DIR/desktop")
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "debian" ]]; then
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
    elif [[ "$distro" == "arch" ]]; then
        case "$desktop" in
            "gnome")
                sudo pacman -S --noconfirm gnome-initial-setup gnome-console gnome-software gnome-tweaks gnome-disk-utility gnome-backgrounds
                sudo systemctl enable gdm
                ;;
            "kde")
                sudo pacman -S --noconfirm plasma-meta konsole dolphin kdeconnect partitionmanager ark
                sudo systemctl enable sddm
                ;;
            "cosmic")
                sudo pacman -S --noconfirm cosmic-session cosmic-terminal cosmic-files cosmic-store cosmic-wallpapers
                sudo systemctl enable cosmic-greeter
                ;;
            "dank")
                curl -fsSL https://install.danklinux.com | sh
                ;;
            "none")
                echo "${YELLOW}Nenhum desktop instalado.${NC}"
                ;;
        esac
    fi
}

setup_network() {
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "debian" ]]; then
        sudo sed -i '/^allow-hotplug /s/^/#/' /etc/network/interfaces
        sudo sed -i '/^iface .* inet /s/^/#/' /etc/network/interfaces
        sudo sed -i '/^iface .* inet6 /s/^/#/' /etc/network/interfaces
    fi
}

setup_performance_vars() {
    sudo mkdir -p /etc/environment.d
    sudo tee /etc/environment.d/performance.conf > /dev/null <<EOF
MESA_SHADER_CACHE_MAX_SIZE=12G
__GL_SHADER_DISK_CACHE_SIZE=12000000000
EOF
}

remove_packages() {
    local distro=$(cat "$STATE_DIR/distro")
    
    if [[ "$distro" == "debian" ]]; then
        sudo apt remove -y nano wget vim-common
        sudo apt autoremove -y
    fi
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
    detect_distro
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
