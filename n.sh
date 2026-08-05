set -euo pipefail

STATE_DIR="/tmp/nixos_install_state"
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "${RED}Este script deve ser executado como root!${NC}"
        echo "   Use: sudo $0"
        exit 1
    fi
}

detect_boot_mode() {
    if [ -d /sys/firmware/efi/efivars ]; then
        echo "uefi" > "$STATE_DIR/boot_mode"
        echo "${GREEN}Modo UEFI detectado.${NC}"
    else
        echo "bios" > "$STATE_DIR/boot_mode"
        echo "${GREEN}Modo BIOS/Legacy detectado.${NC}"
    fi
    sleep 1
}

detect_gpu() {
    local gpu_info=$(lspci -nn 2>/dev/null | grep -E "VGA|3D|Display" | head -1)
    if echo "$gpu_info" | grep -qi "nvidia"; then
        echo "nvidia" > "$STATE_DIR/gpu_driver"
        echo "${GREEN}GPU detectada: NVIDIA${NC}"
    elif echo "$gpu_info" | grep -qi "amd\|radeon"; then
        echo "amd" > "$STATE_DIR/gpu_driver"
        echo "${GREEN}GPU detectada: AMD${NC}"
    elif echo "$gpu_info" | grep -qi "intel"; then
        echo "intel" > "$STATE_DIR/gpu_driver"
        echo "${GREEN}GPU detectada: Intel${NC}"
    else
        echo "nvidia" > "$STATE_DIR/gpu_driver"
        echo "${YELLOW}Não foi possível detectar a GPU. Usando NVIDIA como padrão.${NC}"
    fi
    sleep 1
}

detect_device_type() {
    if [ -f /sys/class/dmi/id/chassis_type ]; then
        local chassis_type=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "0")
        case "$chassis_type" in
            8|9|10|11|12|13|14|15|30|31|32)
                echo "laptop" > "$STATE_DIR/device_type"
                echo "${GREEN}Tipo detectado: Laptop${NC}"
                ;;
            *)
                echo "desktop" > "$STATE_DIR/device_type"
                echo "${GREEN}Tipo detectado: Desktop${NC}"
                ;;
        esac
    else
        echo "desktop" > "$STATE_DIR/device_type"
        echo "${YELLOW}Não foi possível detectar o tipo de dispositivo. Usando Desktop como padrão.${NC}"
    fi
    sleep 1
}

select_language() {
    clear_screen
    show_section "IDIOMA DO SISTEMA / SYSTEM LANGUAGE"
    show_option "1" "Português Brasileiro (pt_BR.UTF-8)"
    show_option "2" "English US (en_US.UTF-8)"
    echo ""
    read -p "Opção [1-2]: " lang_opt
    case "$lang_opt" in
        1) echo "pt_BR.UTF-8" > "$STATE_DIR/lang"
           echo "${GREEN}Idioma: Português Brasileiro${NC}" ;;
        2) echo "en_US.UTF-8" > "$STATE_DIR/lang"
           echo "${GREEN}Idioma: English US${NC}" ;;
        *) echo "pt_BR.UTF-8" > "$STATE_DIR/lang"
           echo "${YELLOW}Opção inválida. Usando Português Brasileiro (padrão).${NC}" ;;
    esac
    sleep 1
}

select_keyboard() {
    clear_screen
    show_section "LAYOUT DO TECLADO / KEYBOARD LAYOUT"
    show_option "1" "Português Brasileiro (br-abnt2)"
    show_option "2" "English US (us) - com teclas mortas"
    echo ""
    read -p "Opção [1-2]: " kb_opt
    case "$kb_opt" in
        1) echo "br-abnt2" > "$STATE_DIR/console_keymap"
           echo "br" > "$STATE_DIR/xkb_layout"
           echo "abnt2" > "$STATE_DIR/xkb_variant"
           echo "${GREEN}Teclado: Português Brasileiro${NC}" ;;
        2) echo "us" > "$STATE_DIR/console_keymap"
           echo "us" > "$STATE_DIR/xkb_layout"
           echo "intl" > "$STATE_DIR/xkb_variant"
           echo "${GREEN}Teclado: English US (internacional com teclas mortas)${NC}" ;;
        *) echo "us" > "$STATE_DIR/console_keymap"
           echo "us" > "$STATE_DIR/xkb_layout"
           echo "intl" > "$STATE_DIR/xkb_variant"
           echo "${YELLOW}Opção inválida. Usando English US (internacional com teclas mortas - padrão).${NC}" ;;
    esac
    sleep 1
}

select_timezone() {
    clear_screen
    show_section "FUSO HORÁRIO / TIMEZONE"
    show_option "1" "America/Fortaleza (Brasil)"
    show_option "2" "America/New_York (EUA)"
    echo ""
    read -p "Opção [1-2]: " tz_opt
    case "$tz_opt" in
        1) echo "America/Fortaleza" > "$STATE_DIR/timezone"
           echo "${GREEN}Fuso: America/Fortaleza${NC}" ;;
        2) echo "America/New_York" > "$STATE_DIR/timezone"
           echo "${GREEN}Fuso: America/New_York${NC}" ;;
        *) echo "America/Fortaleza" > "$STATE_DIR/timezone"
           echo "${YELLOW}Opção inválida. Usando America/Fortaleza (padrão).${NC}" ;;
    esac
    sleep 1
}

select_hostname() {
    clear_screen
    show_section "NOME DO COMPUTADOR / HOSTNAME"
    read -p "Digite o nome do computador [nixos]: " hostname
    if [ -z "$hostname" ]; then
        echo "nixos" > "$STATE_DIR/hostname"
        echo "${YELLOW}Hostname: nixos (padrão)${NC}"
    else
        echo "$hostname" > "$STATE_DIR/hostname"
        echo "${GREEN}Hostname: $hostname${NC}"
    fi
    sleep 1
}

select_username() {
    clear_screen
    show_section "CRIAÇÃO DE USUÁRIO / CREATE USER"
    local fullname=""
    while [ -z "$fullname" ]; do
        read -p "Digite o nome completo do usuário: " fullname
        if [ -z "$fullname" ]; then
            echo "${RED}Nome não pode ser vazio!${NC}"
        fi
    done
    local username=$(echo "$fullname" | tr '[:upper:]' '[:lower:]' | sed 's/  */-/g' | sed 's/[^a-z0-9-]//g')
    if [ -z "$username" ]; then
        username="user"
    fi
    echo "$username" > "$STATE_DIR/username"
    echo "$fullname" > "$STATE_DIR/user_description"
    echo "${GREEN}Nome de usuário: $username${NC}"
    echo "${GREEN}Nome completo: $fullname${NC}"
    sleep 1
    while true; do
        read -s -p "Digite a senha: " userpass
        echo
        read -s -p "Confirme a senha: " userpass2
        echo
        if [ "$userpass" = "$userpass2" ] && [ -n "$userpass" ]; then
            if command -v mkpasswd >/dev/null 2>&1; then
                echo "$(mkpasswd -m sha-512 "$userpass")" > "$STATE_DIR/pass_hash"
            else
                echo "$(openssl passwd -6 "$userpass")" > "$STATE_DIR/pass_hash"
            fi
            echo "${GREEN}Senha definida com sucesso.${NC}"
            sleep 1
            break
        else
            echo "${RED}Senhas não conferem ou estão vazias. Tente novamente.${NC}"
        fi
    done
}

select_desktop() {
    clear_screen
    show_section "AMBIENTE DESKTOP / DESKTOP ENVIRONMENT"
    show_option "1" "COSMIC (Wayland)"
    show_option "2" "GNOME (Wayland)"
    show_option "3" "KDE Plasma (Wayland)"
    show_option "4" "Nenhum (apenas terminal)"
    echo ""
    read -p "Opção [1-4]: " de_opt
    case "$de_opt" in
        1) echo "cosmic" > "$STATE_DIR/desktop"
           echo "${GREEN}Desktop: COSMIC (Wayland)${NC}" ;;
        2) echo "gnome" > "$STATE_DIR/desktop"
           echo "${GREEN}Desktop: GNOME (Wayland)${NC}" ;;
        3) echo "plasma" > "$STATE_DIR/desktop"
           echo "${GREEN}Desktop: KDE Plasma (Wayland)${NC}" ;;
        4) echo "none" > "$STATE_DIR/desktop"
           echo "${GREEN}Desktop: Nenhum (Terminal)${NC}" ;;
        *) echo "cosmic" > "$STATE_DIR/desktop"
           echo "${YELLOW}Opção inválida. Usando COSMIC (padrão).${NC}" ;;
    esac
    sleep 1
}

select_encryption() {
    clear_screen
    show_section "CRIPTOGRAFIA / ENCRYPTION"
    echo "${YELLOW}ATENÇÃO: A criptografia protege seus dados contra acesso não autorizado.${NC}"
    echo "   Será solicitada uma senha na inicialização do sistema."
    echo ""
    local resposta
    read -p "Criptografar o disco com LUKS? (s/n): " -n 1 resposta
    echo
    if [[ "$resposta" =~ ^[Ss]$ ]]; then
        echo "yes" > "$STATE_DIR/encryption"
        echo "${GREEN}Criptografia: Habilitada${NC}"
    else
        echo "no" > "$STATE_DIR/encryption"
        echo "${YELLOW}Criptografia: Desabilitada (padrão)${NC}"
    fi
    sleep 1
}

detect_disks() {
    clear_screen
    show_section "DISCOS DISPONÍVEIS"
    echo "  NÚMERO  DISCO       TAMANHO   MODELO"
    echo "  ──────────────────────────────────────"
    local i=0
    declare -A DISK_MAP
    while IFS= read -r line; do
        local disk=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local model=$(echo "$line" | awk '{$1=$2=""; print $0}' | sed 's/^[ \t]*//')
        if [[ "$disk" =~ ^[a-zA-Z] ]] && [ ! -z "$disk" ]; then
            i=$((i+1))
            printf "  %-6s  %-10s  %-8s  %s\n" "$i)" "/dev/$disk" "$size" "$model"
            DISK_MAP[$i]="/dev/$disk"
        fi
    done < <(lsblk -d -o NAME,SIZE,MODEL 2>/dev/null | grep -v "loop" | tail -n +2)
    if [ $i -eq 0 ]; then
        echo "${RED}Nenhum disco encontrado.${NC}"
        exit 1
    fi
    echo ""
    echo "${RED}ATENÇÃO: O disco selecionado será completamente APAGADO!${NC}"
    echo ""
    while true; do
        read -p "Selecione o número do disco para instalação: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$i" ]; then
            local selected_disk="${DISK_MAP[$choice]}"
            echo "$selected_disk" > "$STATE_DIR/disk"
            echo "${GREEN}Disco selecionado: $selected_disk${NC}"
            break
        else
            echo "${RED}Opção inválida. Tente novamente.${NC}"
        fi
    done
    echo ""
    sleep 1
}

wipe_disk() {
    local disk=$(cat "$STATE_DIR/disk")
    local boot_mode=$(cat "$STATE_DIR/boot_mode")
    local encryption=$(cat "$STATE_DIR/encryption")
    
    clear_screen
    show_section "PARTICIONANDO DISCO"
    
    echo "Limpando tabela de partições existente..."
    
    for part in $(ls ${disk}* 2>/dev/null || true); do
        sudo umount "$part" 2>/dev/null || true
        sudo swapoff "$part" 2>/dev/null || true
    done
    
    if command -v sgdisk >/dev/null 2>&1; then
        echo "  • Usando sgdisk..."
        sudo sgdisk -Z "$disk" 2>/dev/null || true
        sleep 1
        
        if [ "$boot_mode" = "uefi" ]; then
            sudo sgdisk -n 1:1M:+1G -t 1:EF00 -n 2:0:0 -t 2:8300 "$disk"
        else
            sudo sgdisk -n 1:1M:+1G -t 1:8300 -n 2:0:0 -t 2:8300 "$disk"
        fi
    else
        echo "  • Usando parted..."
        if [ "$boot_mode" = "uefi" ]; then
            sudo parted -s "$disk" mklabel gpt || true
            sudo parted -s "$disk" mkpart primary fat32 1MiB 1GiB || true
            sudo parted -s "$disk" set 1 esp on || true
            sudo parted -s "$disk" mkpart primary 1GiB 100% || true
        else
            sudo parted -s "$disk" mklabel msdos || true
            sudo parted -s "$disk" mkpart primary 1MiB 1GiB || true
            sudo parted -s "$disk" set 1 boot on || true
            sudo parted -s "$disk" mkpart primary 1GiB 100% || true
        fi
    fi
    
    sudo partprobe "$disk" 2>/dev/null || true
    sudo udevadm settle
    sleep 2
    
    echo "${GREEN}Tabela de partições criada com sucesso.${NC}"
    
    local boot_part=""
    local root_part=""
    
    if [[ "$disk" == *"nvme"* ]]; then
        boot_part="${disk}p1"
        root_part="${disk}p2"
    else
        boot_part="${disk}1"
        root_part="${disk}2"
    fi
    
    if [ ! -b "$boot_part" ] || [ ! -b "$root_part" ]; then
        echo "${YELLOW}Tentando identificar partições com lsblk...${NC}"
        boot_part=$(lsblk -lno NAME,TYPE "$disk" 2>/dev/null | grep "part" | head -1 | awk '{print "/dev/"$1}')
        root_part=$(lsblk -lno NAME,TYPE "$disk" 2>/dev/null | grep "part" | tail -1 | awk '{print "/dev/"$1}')
    fi
    
    if [ ! -b "$boot_part" ] || [ ! -b "$root_part" ]; then
        echo "${RED}Erro: Partições não foram criadas corretamente.${NC}"
        echo "Boot: $boot_part"
        echo "Root: $root_part"
        exit 1
    fi
    
    echo "${GREEN}Partições identificadas:${NC}"
    echo "  • Boot: $boot_part (1GB)"
    echo "  • Root: $root_part"
    echo ""
    
    echo "Formatando partição boot..."
    if [ "$boot_mode" = "uefi" ]; then
        sudo mkfs.fat -F 32 -n NIXBOOT "$boot_part"
    else
        sudo mkfs.ext4 -F -L NIXBOOT "$boot_part"
    fi
    echo "${GREEN}Boot formatado.${NC}"
    
    local root_device="$root_part"
    if [ "$encryption" = "yes" ]; then
        echo ""
        echo "Configurando criptografia LUKS..."
        local luks_pass=""
        while true; do
            read -s -p "Digite a senha para criptografar o disco: " luks_pass
            echo
            read -s -p "Confirme a senha: " luks_pass2
            echo
            if [ "$luks_pass" = "$luks_pass2" ] && [ -n "$luks_pass" ]; then
                break
            else
                echo "${RED}Senhas não conferem ou vazias. Tente novamente.${NC}"
            fi
        done
        echo -n "$luks_pass" | sudo cryptsetup luksFormat --batch-mode "$root_part" -
        echo -n "$luks_pass" | sudo cryptsetup open "$root_part" cryptroot -
        root_device="/dev/mapper/cryptroot"
        local luks_uuid=$(sudo blkid -s UUID -o value "$root_part")
        echo "$luks_uuid" > "$STATE_DIR/luks_uuid"
        echo "${GREEN}Criptografia configurada.${NC}"
    fi
    
    echo ""
    echo "Formatando partição root (btrfs)..."
    sudo mkfs.btrfs -f -L NIXROOT "$root_device"
    echo "${GREEN}Root formatado.${NC}"
    echo ""
    
    echo "$boot_part" > "$STATE_DIR/boot_part"
    echo "$root_device" > "$STATE_DIR/root_device"
}

mount_partitions() {
    local boot_part=$(cat "$STATE_DIR/boot_part")
    local root_device=$(cat "$STATE_DIR/root_device")
    
    clear_screen
    show_section "MONTANDO PARTIÇÕES"
    
    if [ ! -b "$root_device" ]; then
        echo "${RED}Erro: Dispositivo root não encontrado.${NC}"
        exit 1
    fi
    
    echo "Criando subvolumes btrfs..."
    sudo mount "$root_device" /mnt
    
    sudo btrfs subvolume create /mnt/@ > /dev/null 2>&1
    sudo btrfs subvolume create /mnt/@home > /dev/null 2>&1
    sudo btrfs subvolume create /mnt/@nix > /dev/null 2>&1
    
    sudo umount /mnt
    
    echo "Montando subvolumes..."
    sudo mount -o compress=zstd,noatime,subvol=@ "$root_device" /mnt
    sudo mkdir -p /mnt/home /mnt/nix
    sudo mount -o compress=zstd,noatime,subvol=@home "$root_device" /mnt/home
    sudo mount -o compress=zstd,noatime,subvol=@nix "$root_device" /mnt/nix
    echo "${GREEN}Subvolumes btrfs montados.${NC}"
    
    echo "Montando boot..."
    sudo mkdir -p /mnt/boot
    sudo mount "$boot_part" /mnt/boot
    echo "${GREEN}Boot montado.${NC}"
    
    echo ""
    echo "Criando swap file temporário para a instalação..."
    local swap_size_mb=4096
    local available_space=$(df -m /mnt | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt "$((swap_size_mb + 1024))" ]; then
        echo "${YELLOW}Espaço em disco limitado. Reduzindo swap para 2GB.${NC}"
        swap_size_mb=2048
    fi
    
    local swap_file="/mnt/swapfile"
    
    if btrfs filesystem mkswapfile --size "${swap_size_mb}M" "$swap_file" 2>/dev/null; then
        echo "${GREEN}Swap criado com btrfs.${NC}"
    else
        echo "${YELLOW}Fallback: Criando swap manualmente...${NC}"
        sudo truncate -s 0 "$swap_file"
        sudo fallocate -l "${swap_size_mb}M" "$swap_file" 2>/dev/null || sudo dd if=/dev/zero of="$swap_file" bs=1M count=$swap_size_mb status=progress 2>/dev/null
        sudo chmod 600 "$swap_file"
        sudo mkswap "$swap_file" > /dev/null 2>&1
    fi
    
    sudo swapon "$swap_file" 2>/dev/null || {
        echo "${RED}Erro ao ativar swap. Tentando método alternativo...${NC}"
        sudo truncate -s 0 "$swap_file"
        sudo dd if=/dev/zero of="$swap_file" bs=1M count=$swap_size_mb status=progress 2>/dev/null
        sudo chmod 600 "$swap_file"
        sudo mkswap "$swap_file" > /dev/null 2>&1
        sudo swapon "$swap_file"
    }
    
    echo "${GREEN}Swap temporário configurado: ${swap_size_mb}MB${NC}"
    echo "${YELLOW}NOTA: Este swap será removido após a instalação.${NC}"
    echo ""
}

remove_temporary_swap() {
    echo "Removendo swap temporário da instalação..."
    sudo swapoff /mnt/swapfile 2>/dev/null || true
    sudo rm -f /mnt/swapfile 2>/dev/null || true
    echo "${GREEN}Swap temporário removido.${NC}"
}

generate_config() {
    clear_screen
    show_section "GERANDO CONFIGURAÇÃO"
    
    echo "Gerando hardware-configuration.nix..."
    sudo umount /mnt/boot 2>/dev/null || true
    sudo nixos-generate-config --root /mnt
    local boot_part=$(cat "$STATE_DIR/boot_part")
    sudo mount "$boot_part" /mnt/boot 2>/dev/null || true
    
    local lang=$(cat "$STATE_DIR/lang")
    local console_keymap=$(cat "$STATE_DIR/console_keymap")
    local xkb_layout=$(cat "$STATE_DIR/xkb_layout")
    local xkb_variant=$(cat "$STATE_DIR/xkb_variant")
    local timezone=$(cat "$STATE_DIR/timezone")
    local hostname=$(cat "$STATE_DIR/hostname")
    local username=$(cat "$STATE_DIR/username")
    local user_description=$(cat "$STATE_DIR/user_description")
    local pass_hash=$(cat "$STATE_DIR/pass_hash")
    local device_type=$(cat "$STATE_DIR/device_type")
    local boot_mode=$(cat "$STATE_DIR/boot_mode")
    local desktop=$(cat "$STATE_DIR/desktop")
    local encryption=$(cat "$STATE_DIR/encryption")
    local gpu_driver=$(cat "$STATE_DIR/gpu_driver")
    local disk=$(cat "$STATE_DIR/disk")
    local luks_uuid=$(cat "$STATE_DIR/luks_uuid" 2>/dev/null || echo "")
    local config_file="/mnt/etc/nixos/configuration.nix"
    
    echo "Criando configuration.nix..."
    
    sudo tee "$config_file" > /dev/null << 'EOF'
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];
  nixpkgs.config.allowUnfree = true;
EOF
    sudo tee -a "$config_file" > /dev/null << EOF
  boot.loader.limine.enable = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernelParams = [
    "quiet"
    "splash"
    "transparent_hugepage=always"
    "preempt=full"
  ];
  boot.kernel.sysctl = {
    "kernel.split_lock_mitigate" = 0;
    "kernel.nmi_watchdog" = 0;
    "net.core.netdev_max_backlog" = 4096;
    "fs.file-max" = 2097152;
    "net.ipv4.tcp_congestion_control" = "bbr";
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
  };
EOF
    if [ "$encryption" = "yes" ] && [ -n "$luks_uuid" ]; then
        sudo tee -a "$config_file" > /dev/null << EOF
  boot.initrd = {
    luks.devices."cryptroot" = {
      device = "/dev/disk/by-uuid/$luks_uuid";
      preLVM = true;
    };
    availableKernelModules = [ "aesni_intel" "cryptd" ];
  };
EOF
    fi
    if [ "$gpu_driver" = "amd" ]; then
        sudo tee -a "$config_file" > /dev/null << EOF
  boot.kernelParams = [
    "amdgpu.si_support=1"
    "radeon.si_support=0"
    "amdgpu.cik_support=1"
    "radeon.cik_support=0"
  ];
EOF
    fi
    sudo tee -a "$config_file" > /dev/null << EOF

  networking.hostName = "$hostname";
  networking.networkmanager.enable = true;
  # networking.networkmanager.wifi.backend = "iwd";
  # networking.wireless.iwd.enable = true;
  # networking.wireless.iwd.settings = {
  #   Network = { EnableIPv6 = true; };
  #   Settings = { AutoConnect = true; };
  # };
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 53317 ];
    allowedUDPPorts = [ 53317 ];
    allowedUDPPortRanges = [
      { from = 1714; to = 1764; }
    ];
    allowedTCPPortRanges = [
      { from = 1714; to = 1764; }
    ];
  };
  time.timeZone = "$timezone";
  i18n.defaultLocale = "$lang";
EOF
    if [ "$lang" = "pt_BR.UTF-8" ]; then
        sudo tee -a "$config_file" > /dev/null << EOF
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pt_BR.UTF-8";
    LC_IDENTIFICATION = "pt_BR.UTF-8";
    LC_MEASUREMENT = "pt_BR.UTF-8";
    LC_MONETARY = "pt_BR.UTF-8";
    LC_NAME = "pt_BR.UTF-8";
    LC_NUMERIC = "pt_BR.UTF-8";
    LC_PAPER = "pt_BR.UTF-8";
    LC_TELEPHONE = "pt_BR.UTF-8";
    LC_TIME = "pt_BR.UTF-8";
  };
EOF
    fi
    sudo tee -a "$config_file" > /dev/null << EOF
  console.keyMap = "$console_keymap";
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "$xkb_layout";
EOF
    if [ -n "$xkb_variant" ]; then
        sudo tee -a "$config_file" > /dev/null << EOF
    variant = "$xkb_variant";
EOF
    fi
    sudo tee -a "$config_file" > /dev/null << EOF
  };
  security.rtkit.enable = true;
EOF
    sudo tee -a "$config_file" > /dev/null << EOF
  programs.nano.enable = false;
EOF
    sudo tee -a "$config_file" > /dev/null << EOF
  services.xserver.excludePackages = [ pkgs.xterm ];
EOF
    case $desktop in
        "cosmic")
            sudo tee -a "$config_file" > /dev/null << EOF
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;
  environment.cosmic.excludePackages = with pkgs; [
    cosmic-player
    cosmic-edit
  ];
EOF
            ;;
        "gnome")
            sudo tee -a "$config_file" > /dev/null << EOF
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  environment.gnome.excludePackages = with pkgs; [
    totem
    epiphany
  ];
EOF
            ;;
        "plasma")
            sudo tee -a "$config_file" > /dev/null << EOF
  services.displayManager.plasma-login-manager.enable = true;
  services.desktopManager.plasma6.enable = true;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    elisa
    kate
  ];
EOF
            ;;
    esac
    sudo tee -a "$config_file" > /dev/null << EOF
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
EOF
    sudo tee -a "$config_file" > /dev/null << EOF
  # hardware.bluetooth = {
  #   enable = true;
  #   settings = { General = { Experimental = true; }; };
  # };
  # services.blueman.enable = true;
EOF
    sudo tee -a "$config_file" > /dev/null << EOF
  # services.avahi = {
  #   enable = true;
  #   nssmdns4 = true;
  #   openFirewall = true;
  #   publish = {
  #     enable = true;
  #     userServices = true;
  #   };
  # };
  # services.printing = {
  #   enable = true;
  #   drivers = with pkgs; [ gutenprint cups-filters cups-browsed ];
  #   browsing = true;
  #   defaultShared = true;
  #   openFirewall = true;
  # };
EOF
    sudo tee -a "$config_file" > /dev/null << EOF
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };
EOF
    if [ "$gpu_driver" = "nvidia" ]; then
        sudo tee -a "$config_file" > /dev/null << EOF
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = $([ "$device_type" = "laptop" ] && echo "true" || echo "false");
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };
EOF
    elif [ "$gpu_driver" = "amd" ]; then
        sudo tee -a "$config_file" > /dev/null << EOF
  services.xserver.videoDrivers = [ "modesetting" ];
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };
  environment.variables = {
    MESA_SHADER_CACHE_MAX_SIZE = "12G";
    GSK_RENDERER = "gl";
  };
EOF
    else
        sudo tee -a "$config_file" > /dev/null << EOF
  services.xserver.videoDrivers = [ "modesetting" ];
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-compute-runtime
      intel-media-driver
      vpl-gpu-rt
    ];
  };
  environment.variables = {
    LIBVA_DRIVER_NAME = "iHD";
    MESA_SHADER_CACHE_MAX_SIZE = "12G";
    GSK_RENDERER = "gl";
  };
EOF
    fi
    if [ "$device_type" = "laptop" ]; then
        sudo tee -a "$config_file" > /dev/null << EOF
  powerManagement.enable = true;
  services.thermald.enable = true;
EOF
    else
        sudo tee -a "$config_file" > /dev/null << EOF
  powerManagement.cpuFreqGovernor = "performance";
EOF
    fi
    sudo tee -a "$config_file" > /dev/null << EOF
  services.earlyoom = {
    enable = true;
    freeSwapThreshold = 2;
    freeMemThreshold = 2;
    extraArgs = [
      "-g" "--avoid" "'^(X|plasma.*|konsole|kwin|wayland|gnome.*)$'"
    ];
  };
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
  };
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", \
      ATTR{queue/scheduler}="bfq"
    ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", \
      ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", \
      ATTR{queue/scheduler}="none"
    KERNEL=="rtc0", GROUP="audio"
    KERNEL=="hpet", GROUP="audio"
    DEVPATH=="/devices/virtual/misc/cpu_dma_latency", OWNER="root", GROUP="audio", MODE="0660"
  '';
EOF
    sudo tee -a "$config_file" > /dev/null << EOF
  boot.supportedFilesystems = [ "btrfs" ];
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
  zramSwap.enable = true;
  users.mutableUsers = false;
  users.users.root.hashedPassword = "!";
  users.users.$username = {
    isNormalUser = true;
    description = "$user_description";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "render" ];
    hashedPassword = "$pass_hash";
    shell = pkgs.bash;
  };
  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "SETENV" ];
        }
      ];
    }
  ];
  services.flatpak.enable = true;
  # services.flatpak.packages = [
  #   "com.valvesoftware.Steam"
  #   "app.zen_browser.zen"
  # ];
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };
  environment.systemPackages = with pkgs; [
    fastfetch
    git
    neovim
  ];
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [ "nix-command" "flakes" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 5d";
  };
  system.autoUpgrade = {
    enable = true;
    dates = "daily";
    allowReboot = false;
  };
  fonts.packages = with pkgs; [
    nerd-fonts.adwaita-mono
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];
  hardware.enableAllFirmware = true;
  system.stateVersion = "xx.xx";
}
EOF
    echo "${GREEN}configuration.nix gerado com sucesso.${NC}"
    echo ""
    echo "${YELLOW}ATENÇÃO: O system.stateVersion está como xx.xx.${NC}"
    echo "Substitua xx.xx pela versão correta do NixOS (ex: 25.11)."
    echo ""
    sleep 5
}

generate_flake() {
    clear_screen
    show_section "GERANDO FLAKE.NIX"
    local hostname=$(cat "$STATE_DIR/hostname")
    local flake_file="/mnt/etc/nixos/flake.nix"
    sudo tee "$flake_file" > /dev/null << EOF
{
  description = "NixOS configuration with Chaotic Nyx";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };
  outputs = { self, nixpkgs, chaotic, nix-flatpak } @ inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
      {
        nixosConfigurations = {
          $hostname = nixpkgs.lib.nixosSystem {
            specialArgs = { inherit inputs; };
            system = "x86_64-linux";
            modules = [
              ./configuration.nix
              nix-flatpak.nixosModules.nix-flatpak
              chaotic.nixosModules.default
            ];
          };
        };
      };
  nixConfig = {
    extra-substituters = [
      "https://nyx-cache.chaotic.cx/"
    ];
    extra-trusted-public-keys = [
      "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
    ];
  };
}
EOF
    echo "${GREEN}flake.nix gerado com sucesso.${NC}"
    echo ""
    sleep 1
}

review_configs() {
    clear_screen
    show_section "REVISÃO OBRIGATÓRIA DO CONFIGURATION.NIX"
    echo "ATENÇÃO: Você DEVE revisar o arquivo configuration.nix antes de continuar!"
    echo ""
    echo "${YELLOW}O system.stateVersion está como xx.xx.${NC}"
    echo "${YELLOW}Substitua xx.xx pela versão correta do NixOS (ex: 25.11).${NC}"
    echo ""
    
    local editor="nano"
    if ! command -v nano >/dev/null 2>&1; then
        editor="vi"
    fi
    
    echo "Abrindo /mnt/etc/nixos/configuration.nix para revisão obrigatória..."
    sleep 3
    sudo $editor /mnt/etc/nixos/configuration.nix
    echo ""
    echo "${GREEN}Revisão concluída. Continuando com a instalação...${NC}"
    sleep 2
}

install_system() {
    clear_screen
    show_section "INSTALANDO NIXOS"
    echo "A instalação pode levar alguns minutos..."
    echo ""
    cd /mnt
    sudo -E nixos-install --no-root-passwd
    if [ $? -eq 0 ]; then
        echo "${GREEN}Instalação concluída com sucesso!${NC}"
    else
        echo "${RED}Erro durante a instalação.${NC}"
        exit 1
    fi
    echo ""
}

show_secureboot_guide() {
    clear_screen
    show_section "CONFIGURANDO SECURE BOOT COM LIMINE"
    echo "Para ativar o Secure Boot com Limine, siga estes passos:"
    echo ""
    echo "${CYAN}1. Instale o sbctl:${NC}"
    echo "   sudo nix-env -iA nixpkgs.sbctl"
    echo ""
    echo "${CYAN}2. Gere as chaves Secure Boot:${NC}"
    echo "   sudo sbctl create-keys"
    echo ""
    echo "${CYAN}3. Entre no Setup Mode da UEFI:${NC}"
    echo "   - Reinicie e entre na BIOS/UEFI"
    echo "   - Procure por 'Reset to Setup Mode' ou 'Erase all Secure Boot settings'"
    echo "   - ATENÇÃO: Em Thinkpads, NÃO use 'Clear All Secure Boot Keys'"
    echo ""
    echo "${CYAN}4. Após reiniciar, registre as chaves:${NC}"
    echo "   sudo sbctl enroll-keys --microsoft --firmware-builtin"
    echo ""
    echo "${CYAN}5. Ative o Secure Boot no configuration.nix:${NC}"
    echo "   Adicione: boot.loader.limine.secureBoot.enable = true;"
    echo ""
    echo "${CYAN}6. Reconstrua o sistema:${NC}"
    echo "   sudo nixos-rebuild switch --flake /etc/nixos#$hostname"
    echo ""
    echo "${CYAN}7. Verifique o status:${NC}"
    echo "   bootctl status"
    echo ""
    echo "${YELLOW}Nota: O Secure Boot deve ser reativado manualmente na BIOS após o processo.${NC}"
    echo ""
    read -p "Pressione Enter para continuar..."
}

finish_installation() {
    clear_screen
    show_section "INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    local username=$(cat "$STATE_DIR/username")
    local hostname=$(cat "$STATE_DIR/hostname")
    echo "DETALHES DO SISTEMA:"
    echo "  • Hostname: $hostname"
    echo "  • Usuário: $username"
    echo "  • Desktop: $(cat "$STATE_DIR/desktop")"
    echo "  • GPU: $(cat "$STATE_DIR/gpu_driver")"
    echo "  • Tipo: $(cat "$STATE_DIR/device_type")"
    echo ""
    echo "PRÓXIMOS PASSOS:"
    echo "  1. Remova o USB de instalação"
    echo "  2. Reinicie o sistema"
    echo "  3. Faça login com o usuário $username"
    echo ""
    echo "${YELLOW}⚠ IMPORTANTE: Para ativar o flake, execute após o reboot:${NC}"
    echo "${GREEN}  sudo nixos-rebuild switch --flake /etc/nixos#$hostname${NC}"
    echo ""
    if confirm "Deseja ver o guia para configurar Secure Boot?"; then
        show_secureboot_guide
    fi
    if confirm "Deseja reiniciar o sistema agora?"; then
        echo "Reiniciando em 5 segundos..."
        sleep 5
        reboot
    else
        echo ""
        echo "Digite 'reboot' manualmente quando estiver pronto."
    fi
}

cleanup() {
    echo ""
    echo "Desmontando partições e removendo swap temporário..."
    cd /
    sudo swapoff /mnt/swapfile 2>/dev/null || true
    sudo rm -f /mnt/swapfile 2>/dev/null || true
    sudo umount /mnt/boot 2>/dev/null || true
    sudo umount /mnt/home 2>/dev/null || true
    sudo umount /mnt/nix 2>/dev/null || true
    sudo umount /mnt 2>/dev/null || true
    if [ "$(cat "$STATE_DIR/encryption" 2>/dev/null)" = "yes" ]; then
        sudo cryptsetup close cryptroot 2>/dev/null || true
    fi
    echo "${GREEN}Limpeza concluída.${NC}"
}

show_summary() {
    clear_screen
    show_section "RESUMO DA INSTALAÇÃO"
    printf "  %-25s: %s\n" "Idioma" "$(cat "$STATE_DIR/lang")"
    printf "  %-25s: %s\n" "Teclado" "$(cat "$STATE_DIR/console_keymap")"
    printf "  %-25s: %s\n" "Fuso horário" "$(cat "$STATE_DIR/timezone")"
    printf "  %-25s: %s\n" "Hostname" "$(cat "$STATE_DIR/hostname")"
    printf "  %-25s: %s\n" "Tipo de dispositivo" "$(cat "$STATE_DIR/device_type")"
    printf "  %-25s: %s\n" "Sistema de arquivos" "btrfs"
    printf "  %-25s: %s\n" "Bootloader" "Limine"
    printf "  %-25s: %s\n" "Kernel" "Linux Latest"
    printf "  %-25s: %s\n" "GPU" "$(cat "$STATE_DIR/gpu_driver")"
    printf "  %-25s: %s\n" "Desktop" "$(cat "$STATE_DIR/desktop")"
    printf "  %-25s: %s\n" "Criptografia" "$(cat "$STATE_DIR/encryption")"
    printf "  %-25s: %s\n" "Disco" "$(cat "$STATE_DIR/disk")"
    printf "  %-25s: %s\n" "Usuário" "$(cat "$STATE_DIR/username")"
    echo ""
    echo "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    if ! confirm "Continuar com a instalação?"; then
        echo "Instalação cancelada."
        exit 0
    fi
}

main() {
    check_root
    detect_boot_mode
    detect_gpu
    detect_device_type
    select_language
    select_keyboard
    select_timezone
    select_hostname
    select_username
    select_desktop
    select_encryption
    detect_disks
    show_summary
    wipe_disk
    mount_partitions
    generate_config
    generate_flake
    review_configs
    install_system
    remove_temporary_swap
    finish_installation
}

trap 'echo -e "\n${RED}Erro detectado. A instalação foi interrompida.${NC}"; cleanup; exit 1' ERR INT TERM
main "$@"
