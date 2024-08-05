#!/usr/bin/env bash
# Purpose: Automate the creation of a Talos VM in Proxmox

function header_info {
  clear
  cat <<"EOF"
                                                 
888888888888         88                          
     88              88                          
     88              88                          
     88  ,adPPYYba,  88   ,adPPYba,   ,adPPYba,  
     88  ""     `Y8  88  a8"     "8a  I8[    ""  
     88  ,adPPPPP88  88  8b       d8   `"Y8ba,   
     88  88,    ,88  88  "8a,   ,a8"  aa    ]8I  
     88  `"8bbdP"Y8  88   `"YbbdP"'   `"YbbdP"'                                                   

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
NEXTID=111  # Default VM ID to 111

# Terminal color codes for enhancing output readability.
CL="\033[m"
GN="\033[1;92m"
RD="\033[01;31m"
DGN="\033[32m"
BGN="\033[4;92m"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

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

if ! whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "Talos VM" --yesno "This will create a New Talos VM. Proceed?" 10 58; then
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
    if ! whiptail --backtitle "Proxmox VE Talos Linux Install Script" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
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
  HN="TalosVM$VMID"
  CPU_TYPE="host"
  CORE_COUNT="2"
  RAM_SIZE="2048"
  DISK_SIZE="80G"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU="1500"
  START_VM="yes"
  VM_TAG="kubernetes"
  EFI_DISK_SIZE="512M"
  echo -e "${DGN}Default settings applied.${CL}"
}

function advanced_settings() {
  check_vmid
  VMID=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "Virtual Machine ID (Default: $NEXTID)" 8 60 $NEXTID --title "VIRTUAL MACHINE ID" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  HN=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "Hostname (Default: TalosVM$VMID)" 8 60 "TalosVM$VMID" --title "HOSTNAME" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  MACHINE=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "MACHINE TYPE" --radiolist "Select machine type:" 10 60 2 "q35" "Q35: Modern with PCIe support (recommended)" ON "i440fx" "Older, less feature-rich" OFF 3>&1 1>&2 2<&3 || exit_script)
  DISK_CACHE=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "DISK CACHE" --radiolist "Disk cache type:" 10 60 2 "none" "None (recommended for data integrity)" ON "writeback" "Better performance, higher risk" OFF 3>&1 1>&2 2<&3 || exit_script)
  CPU_TYPE=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "CPU MODEL" --radiolist "CPU model:" 10 60 2 "host" "Host (use host CPU features)" ON "kvm64" "Generic, less optimized" OFF 3>&1 1>&2 2<&3 || exit_script)
  CORE_COUNT=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "Number of CPU cores (Default: 2)" 8 60 "2" --title "CPU CORES" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  RAM_SIZE=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "RAM size in MiB (Default: 2048)" 8 60 "2048" --title "RAM SIZE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  DISK_SIZE=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "Disk size (Default: 80G)" 8 60 "80G" --title "DISK SIZE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  BRG=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "Network Bridge (Default: vmbr0)" 8 60 "vmbr0" --title "NETWORK BRIDGE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  MAC=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "MAC Address (Auto-generated: $GEN_MAC)" 8 60 $GEN_MAC --title "MAC ADDRESS" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  VLAN=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "VLAN Tag (Optional)" 8 60 --title "VLAN TAG" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  MTU=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "Interface MTU Size (Default: 1500)" 8 60 "1500" --title "MTU SIZE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  VM_TAG=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "VM Tag for identification (Default: kubernetes)" 8 60 "kubernetes" --title "VM TAG" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  EFI_DISK_SIZE=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --inputbox "EFI Disk Size (Default: 512M)" 8 60 "512M" --title "EFI DISK SIZE" --cancel-button exit_script 3>&1 1>&2 2<&3 || exit_script)
  START_VM=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 60 && echo "yes" || echo "no")
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "SETTINGS" --yesno "Use Default Settings?" --defaultno 10 60); then
    default_settings
  else
    advanced_settings
  fi
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
STORAGE=$(whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "Storage Pools" --radiolist \
  "Which storage pool you would like to use for ${HN}?\nTo make a selection, use the Spacebar." \
  16 80 6 "${STORAGE_MENU[@]}" 3>&1 1>&2 2<&3)

# Default to the first storage option if no selection is made.
if [ -z "$STORAGE" ]; then
  STORAGE="${STORAGE_MENU[0]}"
fi

msg_ok "Using $STORAGE for Storage Location."
msg_ok "Virtual Machine ID is $VMID."

# Retrieve and download the Talos ISO.
msg_info "Retrieving the URL for the Talos ISO Disk Image"
ISO_URL="https://github.com/siderolabs/talos/releases/latest/download/metal-amd64.iso"
RELEASE_DATE=$(curl -s https://api.github.com/repos/siderolabs/talos/releases/latest | grep '"published_at"' | sed -E 's/.*"([^"]+)".*/\1/' | cut -d'T' -f1 | sed 's/-//g')
ISO_FILE="${RELEASE_DATE}-talos-metal-amd64.iso"
ISO_PATH="/var/lib/vz/template/iso/$ISO_FILE"

# Check if the ISO file already exists
if [ -f "$ISO_PATH" ]; then
    msg_ok "ISO file already exists: $ISO_FILE"
else
    # Download the ISO file
    wget -q --show-progress $ISO_URL -O $ISO_PATH
    echo -en "\e[1A\e[0K"  # Clear the wget progress
    msg_ok "Downloaded $ISO_FILE"
fi

# Create the Talos VM
msg_info "Creating a Talos VM"
qm create $VMID -agent enabled=1 -tablet 0 -localtime 1 -bios ovmf -machine $MACHINE -cpu $CPU_TYPE -cores $CORE_COUNT -memory $RAM_SIZE -name $HN -tags $VM_TAG -net0 virtio,bridge=$BRG,macaddr=$MAC${VLAN:+,vlan-tag=$VLAN}${MTU:+,mtu=$MTU} -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

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
DISK0="vm-${VMID}-disk-1"  # Change to a different name to avoid conflict
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
  -description "# Talos - VM - $VMID - Created $CREATION_DATE - ISO Used: $ISO_USED</div><div align='center'><a href='https://www.talos.dev/' target='_blank' rel='noopener noreferrer'><img src='https://avatars.githubusercontent.com/u/13804887?s=200&v=4'/></a><br><br>"

msg_ok "Created a Talos VM (${HN})"

# Ask the user if they want to start the VM.
if (whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "START VIRTUAL MACHINE" --yesno "Would you like to start the VM now?" 10 60); then
  msg_info "Starting Talos VM"
  qm start $VMID
  msg_ok "Started Talos VM"

  whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "INSTALL TALOS" --msgbox "Install Talos to the VM now. When complete, press Enter." 10 60

  if (whiptail --backtitle "Proxmox VE Talos Linux Install Script" --title "REMOVE CD DRIVE" --yesno "Remove Mounted CD drive device from VM and set boot to VM drive?" 10 60); then
    qm stop $VMID
    msg_info "Removing CD drive and setting boot to VM drive"
    qm set $VMID -delete ide2
    qm set $VMID -boot order=scsi0
    qm start $VMID
    msg_ok "Removed CD drive and set boot to VM drive"
  else
    msg_info "CD drive not removed. Boot order unchanged."
  fi
else
  msg_info "VM creation complete. VM not started."
fi

msg_ok "Completed Successfully!"
cleanup
