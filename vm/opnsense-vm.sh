#!/usr/bin/env bash
# Purpose: Automate the creation of an OPNsense VM in Proxmox

function header_info {
    clear
  cat <<"EOF"

                          (               (
  (   `  )    (     (    ))\  (     (    ))\
  )\  /(/(    )\ )  )\  /((_) )\ )  )\  /((_)
 ((_)((_)_\  _(_/( ((_)(_))  _(_/( ((_)(_))
/ _ \| '_ \)| ' \))(_-</ -_)| ' \))(_-</ -_)
\___/| .__/ |_||_| /__/\___||_||_| /__/\___|
     |_|    O P N S E N S E  F I R E W A L L

Press Enter to Continue
EOF
}

# Check next VMID across Proxmox Cluster
function check_vmid {
    while pvesh get /cluster/resources --type vm | grep -qw "$NEXTID"; do
        ((NEXTID++))
    done
    echo "New VMID after increment: $NEXTID"
}

header_info

# Generate a MAC address for the new VM.
GEN_MAC=02:$(openssl rand -hex 5 | sed 's/\(..\)/\1:/g; s/.$//')
NEXTID=100  # Default VM ID to 100

# Terminal color codes for enhancing output readability.
CL="\033[m"
GN="\033[1;92m"
RD="\033[01;31m"
DGN="\033[32m"
BGN="\033[4;92m"
CM="${GN}âœ“${CL}"
CROSS="${RD}âœ—${CL}"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT

function msg_info() {
    echo -e "${GN}Info: $1${CL}"
}

function msg_ok() {
    echo -e "${GN}Success: $1${CL}"
}

function msg_error() {
    echo -e "${RD}Error: $1${CL}"
}

function error_handler() {
    local exit_code=$?
    local line_number=$1
    local command=$2
    echo -e "\n${RD}[ERROR]${CL} in line $line_number: exit code $exit_code: while executing command $command\n"
    cleanup_vmid
}

function cleanup_vmid() {
    if qm status $VMID &>/dev/null; then
        qm stop $VMID &>/dev/null
        qm destroy $VMID &>/dev/null
    fi
}

function cleanup() {
    if [[ -d $TEMP_DIR ]]; then
        rm -rf $TEMP_DIR
    fi
}
TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if ! whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "OPNsense VM" --yesno "This will create a New OPNsense VM. Proceed?" 10 58; then
    header_info && echo -e "User exited script \n" && exit
fi

function check_root() {
    # Ensure the script is run as root to avoid permission issues.
    if [[ "$(id -u)" -ne 0 ]]; then
        clear
        msg_error "Please run this script as root."
        echo -e "\nExiting..."
        sleep 2
        exit
    fi
}

function pve_check() {
    # Check for compatible Proxmox VE version.
    if ! pveversion | grep -Eq "pve-manager/8.[1-3]"; then
        msg_error "This version of Proxmox Virtual Environment is not supported"
        echo -e "Requires Proxmox Virtual Environment Version 8.1 or later."
        echo -e "Exiting..."
        sleep 2
        exit
    fi
}

function arch_check() {
    # Ensure the script is running on an AMD64 architecture.
    if [ "$(dpkg --print-architecture)" != "amd64" ]; then
        msg_error "This script will not work with PiMox! \n"
        echo -e "Exiting..."
        sleep 2
        exit
    fi
}

function ssh_check() {
    # Warn about potential issues when running the script over SSH.
    if [ -n "${SSH_CLIENT:+x}" ]; then
        if ! whiptail --backtitle "Proxmox VE OPNsense Install Script" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
            clear
            exit
        fi
    fi
}

function exit_script() {
  clear
  echo -e "User exited script \n"
  exit 1
}

function default_settings() {
    check_vmid
    VMID="$NEXTID"
    FORMAT=",efitype=4m"
    MACHINE="q35"
    DISK_CACHE=""
    HN="OPNsense$VMID"
    CPU_TYPE="host"
    CORE_COUNT="2"
    RAM_SIZE="2048"
    DISK_SIZE="80G"
    BRG="vmbr0"
    MAC="$GEN_MAC"
    VLAN=""
    MTU="1500"
    START_VM="yes"
    VM_TAG="firewall"
    EFI_DISK_SIZE="512M"
    echo -e "${DGN}Default settings applied.${CL}"
}

function advanced_settings() {
    check_vmid
    VMID=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "Virtual Machine ID (Default: $NEXTID)" 8 60 $NEXTID --title "VIRTUAL MACHINE ID" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    HN=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "Hostname (Default: OPNsense$VMID)" 8 60 "OPNsense$VMID" --title "HOSTNAME" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    MACHINE=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "MACHINE TYPE" --radiolist "Select machine type:" 10 60 2 "q35" "Q35: Modern with PCIe support (recommended)" ON "i440fx" "Older, less feature-rich" OFF 3>&1 1>&2 2<&3 || exit_script)
    DISK_CACHE=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "DISK CACHE" --radiolist "Disk cache type:" 10 60 2 "none" "None (recommended for data integrity)" ON "writeback" "Better performance, higher risk" OFF 3>&1 1>&2 2<&3 || exit_script)
    CPU_TYPE=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "CPU MODEL" --radiolist "CPU model:" 10 60 2 "host" "Host (use host CPU features)" ON "kvm64" "Generic, less optimized" OFF 3>&1 1>&2 2<&3 || exit_script)
    CORE_COUNT=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "Number of CPU cores (Default: 2)" 8 60 "2" --title "CPU CORES" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    RAM_SIZE=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "RAM size in MiB (Default: 2048)" 8 60 "2048" --title "RAM SIZE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    DISK_SIZE=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "Disk size (Default: 80G)" 8 60 "80G" --title "DISK SIZE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    BRG=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "Network Bridge (Default: vmbr0)" 8 60 "vmbr0" --title "NETWORK BRIDGE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    MAC=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "MAC Address (Auto-generated: $GEN_MAC)" 8 60 $GEN_MAC --title "MAC ADDRESS" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    VLAN=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "VLAN Tag (Optional)" 8 60 --title "VLAN TAG" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    MTU=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "Interface MTU Size (Default: 1500)" 8 60 "1500" --title "MTU SIZE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    VM_TAG=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "VM Tag for identification (Default: firewall)" 8 60 "firewall" --title "VM TAG" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    EFI_DISK_SIZE=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "EFI Disk Size (Default: 512M)" 8 60 "512M" --title "EFI DISK SIZE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
    START_VM=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 60 && echo "yes" || echo "no")
}

function start_script() {
    if (whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "SETTINGS" --yesno "Use Default Settings?" --defaultno 10 60); then
        default_settings
    else
        advanced_settings
    fi
}

function prompt_root_password() {
    ROOT_PASSWORD=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "ROOT PASSWORD" --passwordbox "Enter root password:" 10 60 3>&1 1>&2 2>&3)
    if [ -z "$ROOT_PASSWORD" ]; then
        msg_error "No password entered. Exiting..."
        exit 1
    fi
}

function prompt_network_configuration() {
    echo "Starting network configuration..."
    LAN_IPV4=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "Enter LAN IPv4 Address:" 8 60 --title "LAN IPv4 ADDRESS" 3>&1 1>&2 2>&3)
    echo "LAN_IPV4 prompt completed."
    if [ -z "$LAN_IPV4" ]; then
        msg_error "No LAN IPv4 Address entered. Exiting..."
        exit 1
    fi
    echo "LAN IPv4 Address: $LAN_IPV4"
    SUBNET_MASK=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "Enter Subnet Mask (CIDR format):" 8 60 --title "SUBNET MASK" 3>&1 1>&2 2>&3)
    echo "SUBNET_MASK prompt completed."
    if [ -z "$SUBNET_MASK" ]; then
        msg_error "No Subnet Mask entered. Exiting..."
        exit 1
    fi
    echo "Subnet Mask: $SUBNET_MASK"
    if whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "DHCP SERVER" --yesno "Enable DHCP Server?" 10 60; then
        ENABLE_DHCP="yes"
    else
        ENABLE_DHCP="no"
    fi
    echo "ENABLE_DHCP prompt completed: $ENABLE_DHCP"
    if [ "$ENABLE_DHCP" = "yes" ]; then
        echo "Starting DHCP configuration..."
        DHCP_START=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "Start of DHCP range:" 8 60 --title "DHCP RANGE START" 3>&1 1>&2 2>&3)
        echo "DHCP_START prompt completed."
        if [ -z "$DHCP_START" ]; then
            msg_error "No DHCP Start Range entered. Exiting..."
            exit 1
        fi
        echo "DHCP Start Range: $DHCP_START"
        DHCP_END=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --inputbox "End of DHCP range:" 8 60 --title "DHCP RANGE END" 3>&1 1>&2 2>&3)
        echo "DHCP_END prompt completed."
        if [ -z "$DHCP_END" ]; then
            msg_error "No DHCP End Range entered. Exiting..."
            exit 1
        fi
        echo "DHCP End Range: $DHCP_END"
    else
        echo "Skipping DHCP configuration..."
    fi
    if whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "HTTPS ACCESS" --yesno "Enable HTTPS for Web GUI?" 10 60; then
        ENABLE_HTTPS="y"
    else
        ENABLE_HTTPS="n"
    fi
    echo "ENABLE_HTTPS prompt completed: $ENABLE_HTTPS"
}

function automate_install() {
    function send_line_to_vm() {
        local line="$1"
        for ((i = 0; i < ${#line}; i++)); do
            character=${line:i:1}
            case $character in
                " ") character="spc" ;;
                "-") character="minus" ;;
                "=") character="equal" ;;
                ",") character="comma" ;;
                ".") character="dot" ;;
                "/") character="slash" ;;
                "'") character="apostrophe" ;;
                ";") character="semicolon" ;;
                '\\') character="backslash" ;;
                '`') character="grave_accent" ;;
                "[") character="bracket_left" ;;
                "]") character="bracket_right" ;;
                "_") character="shift-minus" ;;
                "+") character="shift-equal" ;;
                "?") character="shift-slash" ;;
                "<") character="shift-comma" ;;
                ">") character="shift-dot" ;;
                '"') character="shift-apostrophe" ;;
                ":") character="shift-semicolon" ;;
                "|") character="shift-backslash" ;;
                "~") character="shift-grave_accent" ;;
                "{") character="shift-bracket_left" ;;
                "}") character="shift-bracket_right" ;;
                "A") character="shift-a" ;;
                "B") character="shift-b" ;;
                "C") character="shift-c" ;;
                "D") character="shift-d" ;;
                "E") character="shift-e" ;;
                "F") character="shift-f" ;;
                "G") character="shift-g" ;;
                "H") character="shift-h" ;;
                "I") character="shift-i" ;;
                "J") character="shift-j" ;;
                "K") character="shift-k" ;;
                "L") character="shift-l" ;;
                "M") character="shift-m" ;;
                "N") character="shift-n" ;;
                "O") character="shift-o" ;;
                "P") character="shift-p" ;;
                "Q") character="shift-q" ;;
                "R") character="shift-r" ;;
                "S") character="shift-s" ;;
                "T") character="shift-t" ;;
                "U") character="shift-u" ;;
                "V") character="shift-v" ;;
                "W") character="shift-w" ;;
                "X") character="shift-x" ;;
                "Y") character="shift-y" ;;
                "Z") character="shift-z" ;;
                "!") character="shift-1" ;;
                "@") character="shift-2" ;;
                "#") character="shift-3" ;;
                '$') character="shift-4" ;;
                "%") character="shift-5" ;;
                "^") character="shift-6" ;;
                "&") character="shift-7" ;;
                "*") character="shift-8" ;;
                "(") character="shift-9" ;;
                ")") character="shift-0" ;;
            esac
            qm sendkey $VMID "$character"
        done
    }
    
    # Function to press Enter key
    function press_enter() {
        qm sendkey $VMID ret
    }
    
    # Define the automated steps
    function automate_setup() {
        local LAN_IPV4=$1
        local SUBNET_MASK=$2
        local ENABLE_DHCP=$3
        local DHCP_START=$4
        local DHCP_END=$5
        local ENABLE_HTTPS=$6
        echo "Starting OPNsense setup with:"
        echo "LAN_IPV4: $LAN_IPV4"
        echo "SUBNET_MASK: $SUBNET_MASK"
        echo "ENABLE_DHCP: $ENABLE_DHCP"
        echo "DHCP_START: $DHCP_START"
        echo "DHCP_END: $DHCP_END"
        echo "ENABLE_HTTPS: $ENABLE_HTTPS"
        # Wait for initial boot
        sleep 90
        msg_info "VM booted, sending installer command."
        # Start the installer
        send_line_to_vm "installer"
        press_enter
        send_line_to_vm "opnsense"
        press_enter
        echo "Installer command sent."
        # Wait for keymap selection
        sleep 10
        press_enter
        echo "Keymap selection confirmed."
        # Select install filesystem
        sleep 10
        qm sendkey $VMID down
        press_enter
        echo "Filesystem selected."
        # Select disk
        sleep 10
        qm sendkey $VMID down
        press_enter
        echo "Disk selected."
        # Confirm swap
        sleep 10
        press_enter
        echo "Swap confirmed."
        # Confirm destroy
        sleep 5
        qm sendkey $VMID left
        press_enter
        echo "Destroy confirmed."
        # Wait for installation
        sleep 200
        echo "Installation completed."
        # Set root password
        press_enter
        sleep 2
        send_line_to_vm "$ROOT_PASSWORD"
        press_enter
        sleep 2
        send_line_to_vm "$ROOT_PASSWORD"
        press_enter
        echo "Root password set."
        # Confirm reboot
        sleep 20
        qm sendkey $VMID down
        press_enter
        echo "Reboot confirmed."
        # Wait for reboot
        sleep 30
        # Stop the VM
        qm stop $VMID
        echo "VM stopped."
        # Wait for stop
        until qm status $VMID | grep -q "stopped"; do
            sleep 2
        done
        echo "VM is now stopped."
        # Remove CD boot device
        qm set $VMID -delete ide2
        qm set $VMID -boot order=scsi0
        echo "CD boot device removed and boot order set."
        # Start the VM
        qm start $VMID
        sleep 40  # Wait for the VM to start
        echo "VM restarted, proceeding with login."
        # Login as root
        send_line_to_vm "root"
        sleep 2
        press_enter
        send_line_to_vm "$ROOT_PASSWORD"
        sleep 2
        echo "Logged in as root."
        press_enter
        sleep 2
        # Configure network interfaces
        echo "Configuring network interfaces"
        send_line_to_vm "2"
        press_enter
        sleep 3
        send_line_to_vm "n"
        press_enter
        sleep 3
        send_line_to_vm "$LAN_IPV4"
        press_enter
        sleep 3
        send_line_to_vm "$SUBNET_MASK"
        sleep 3
        press_enter
        press_enter  # Skip upstream IP
        sleep 3
        send_line_to_vm "n"  # Configure IPv6
        sleep 3
        press_enter
        sleep 3
        press_enter  # Set IPv6
        sleep 6
        # Enable DHCP server based on user input
        if [ "$ENABLE_DHCP" = "yes" ]; then
            send_line_to_vm "y"
            sleep 3
            press_enter
            send_line_to_vm "$DHCP_START"
            press_enter
            sleep 3
            send_line_to_vm "$DHCP_END"
            press_enter
            sleep 3
            echo "DHCP server configured."
        else
            send_line_to_vm "n"
            sleep 3
            press_enter  # Web GUI access defaults
            sleep 3
        fi
        # Enable HTTPS based on user input
        if [ "$ENABLE_HTTPS" = "y" ]; then
            send_line_to_vm "n"
        else
            send_line_to_vm "y"
            sleep 2
            press_enter
        fi
        sleep 3
        press_enter  # Web GUI cert
        sleep 3
        press_enter  # Web GUI access defaults
        sleep 3
        press_enter
        echo "HTTPS configuration completed."
    }
    automate_setup "$LAN_IPV4" "$SUBNET_MASK" "$ENABLE_DHCP" "$DHCP_START" "$DHCP_END" "$ENABLE_HTTPS"
}

# Run initial system checks before starting configuration.
check_root
arch_check
pve_check
ssh_check
start_script

# Validate available storage before proceeding.
msg_info "Validating Storage"
STORAGE_MENU=()
while read -r line; do
    TAG=$(echo "$line" | awk '{print $1}')
    TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
    FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
    ITEM="Type: $TYPE Free: $FREE"
    STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
if [ ${#STORAGE_MENU[@]} -eq 0 ]; then
    msg_error "Unable to detect a valid storage location."
    exit 1
fi

# Let user select the storage.
STORAGE=$(whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "Storage Pools" --radiolist \
    "Which storage pool you would like to use for ${HN}?\nTo make a selection, use the Spacebar." \
16 80 6 "${STORAGE_MENU[@]}" 3>&1 1>&2 2<&3)

# Default to the first storage option if no selection is made.
if [ -z "$STORAGE" ]; then
    STORAGE="${STORAGE_MENU[0]}"
fi
msg_ok "Using $STORAGE for Storage Location."
msg_ok "Virtual Machine ID is $VMID."

# Retrieve and download the OPNsense ISO.
msg_info "Getting URL for OPNsense Disk Image"

# Fetch the HTML content and extract the release date
release_date=$(curl -s https://mirrors.ocf.berkeley.edu/opnsense/releases/mirror/ | grep -oP '(?<=<td class="date">)[0-9]{4}-[a-zA-Z]{3}-[0-9]{2}(?= [0-9]{2}:[0-9]{2})' | head -1)
echo "Extracted release date: $release_date"

# Check if the release date was extracted
if [[ -z "$release_date" ]]; then
    echo "Error: Release date not found."
    exit 1
fi

# Manually convert the date format
year=$(echo $release_date | cut -d'-' -f1)
month=$(echo $release_date | cut -d'-' -f2)
day=$(echo $release_date | cut -d'-' -f3)
case $month in
    Jan) month="01" ;;
    Feb) month="02" ;;
    Mar) month="03" ;;
    Apr) month="04" ;;
    May) month="05" ;;
    Jun) month="06" ;;
    Jul) month="07" ;;
    Aug) month="08" ;;
    Sep) month="09" ;;
    Oct) month="10" ;;
    Nov) month="11" ;;
    Dec) month="12" ;;
    *) echo "Invalid month"; exit 1 ;;
esac
formatted_date="${year}${month}${day}"
echo "Formatted release date: $formatted_date"

# Define the URL and paths
URL="https://mirrors.ocf.berkeley.edu/opnsense/releases/mirror/OPNsense-24.7-dvd-amd64.iso.bz2"
BZ2_FILE="${formatted_date}-OPNsense-24.7-dvd-amd64.iso.bz2"
ISO_FILE="${formatted_date}-OPNsense-24.7-dvd-amd64.iso"
BZ2_PATH="/var/lib/vz/template/iso/$BZ2_FILE"
ISO_PATH="/var/lib/vz/template/iso/$ISO_FILE"

# Check if the ISO file already exists
if [ -f "$ISO_PATH" ]; then
    msg_ok "ISO file already exists: $ISO_FILE"
else
    # Download the bz2 file
    wget -q --show-progress $URL -O $BZ2_PATH
    echo -en "\e[1A\e[0K"
    msg_ok "Downloaded $BZ2_FILE"
    # Extract the bz2 file
    bunzip2 $BZ2_PATH
    msg_ok "Extracted $BZ2_FILE to $ISO_FILE"
fi

# Determine the appropriate storage type and set up the disk configuration.
STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
    nfs|dir)
        DISK_EXT=".qcow2"
        DISK_REF="$VMID/"
        DISK_IMPORT="-format qcow2"
    ;;
    btrfs)
        DISK_EXT=".qcow2"
        DISK_REF="$VMID/"
        DISK_IMPORT="-format qcow2"
    ;;
esac
DISK0="vm-${VMID}-disk-0${DISK_EXT}"
DISK0_REF="${STORAGE}:${DISK_REF}${DISK0}"

# Create the OPNsense VM with basic settings
msg_info "Creating an OPNsense VM"
qm create $VMID -agent enabled=1 -tablet 0 -localtime 1 -bios ovmf -machine $MACHINE -cpu $CPU_TYPE -cores $CORE_COUNT -memory $RAM_SIZE -name $HN -tags firewall -net0 virtio,bridge=$BRG,macaddr=$MAC${VLAN:+,vlan-tag=$VLAN}${MTU:+,mtu=$MTU} -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

# Check if VM exists
if ! qm status $VMID &>/dev/null; then
    msg_error "Failed to create VM $VMID. Exiting."
    exit 1
fi

# Create EFI disk with appropriate size
msg_info "Creating EFI disk"
qm set $VMID -efidisk0 ${STORAGE}:0,size=${EFI_DISK_SIZE},efitype=4m

# Attach the main disk and ISO
msg_info "Attaching disks and ISO"

# Allocate the disk
msg_info "Allocating disk space"
DISK0="vm-${VMID}-disk-1"
pvesm alloc $STORAGE $VMID $DISK0 $DISK_SIZE

# Retry mechanism for attaching the main disk
RETRY_COUNT=5
RETRY_DELAY=5
for (( i=1; i<=$RETRY_COUNT; i++ )); do
    if qm set $VMID -scsi0 ${STORAGE}:${DISK0}; then
        msg_ok "Main disk attached successfully"
        break
    else
        msg_error "Attempt $i: Failed to attach main disk. Retrying in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
    fi
    if [ $i -eq $RETRY_COUNT ]; then
        msg_error "Exceeded maximum retry attempts to attach main disk. Exiting."
        exit 1
    fi
done
qm set $VMID -ide2 local:iso/$ISO_FILE,media=cdrom

# Ensure boot order includes CD-ROM first and then SCSI
msg_info "Setting boot order"
qm set $VMID -boot order=ide2;order=scsi0

# Set the description for the VM
CREATION_DATE=$(date +"%Y-%m-%d")
ISO_USED=$ISO_FILE
qm set $VMID \
-description "# OPNsense - VM - $VMID - Created $CREATION_DATE - ISO Used: $ISO_USED</div><div align='center'><a href='https://opnsense.org/' target='_blank' rel='noopener noreferrer'><img src='https://icons.iconarchive.com/icons/simpleicons-team/simple/512/opnsense-icon.png'/></a><br><br>"
msg_ok "Created an OPNsense VM (${HN})"

# Check if the user wants to start the VM
if (whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "START VIRTUAL MACHINE" --yesno "Would you like to start the VM now?" 10 60); then
    if (whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "AUTOMATE SETUP" --yesno "Would you like to automate the setup?" 10 60); then
        prompt_root_password  # Prompt for root password
        prompt_network_configuration  # Prompt for network configuration
        msg_info "Starting OPNsense VM"
        qm start $VMID
        msg_info "VM Started. Proceeding to automate the installation."
        automate_install
    else
        msg_info "Starting OPNsense VM"
        qm start $VMID
        whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "INSTALL OPNsense" --msgbox "Install OPNsense to the VM now. When complete, press Enter." 10 60
        if (whiptail --backtitle "Proxmox VE OPNsense Install Script" --title "REMOVE CD DRIVE" --yesno "Remove Mounted CD drive device from VM and set boot to VM drive?" 10 60); then
            qm stop $VMID
            msg_info "Removing CD drive and setting boot to VM drive"
            qm set $VMID -delete ide2
            qm set $VMID -boot order=scsi0
            qm start $VMID
            msg_ok "Removed CD drive and set boot to VM drive"
        else
            msg_info "CD drive not removed. Boot order unchanged."
        fi
    fi
else
    msg_info "VM creation complete. VM not started."
fi
msg_ok "Completed Successfully!"
cleanup
