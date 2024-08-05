=======
# Proxmox Scripts Additions

This repository includes additional scripts for:

- **[Talos VM](https://github.com/Deenyoro/Proxmox-Deen/blob/main/vm/talos-vm.sh)**: Automate the creation of a Talos VM in Proxmox.
- **[OPNsense VM](https://github.com/Deenyoro/Proxmox-Deen/blob/main/vm/opnsense-vm.sh)**: Automate the creation of an OPNsense VM in Proxmox.

Original repository by [tteck](https://github.com/tteck/Proxmox).

---

## Useful One-Line Scripts

### After Install CD Remove Script

```VMID={VMID}; qm stop $VMID; qm wait $VMID; echo "Removing CD drive and setting boot to VM drive"; qm set $VMID -delete ide2; qm set $VMID -boot order=scsi0; qm start $VMID; echo "Removed CD drive, set boot to VM drive, and started the VM"```


### Stop VM Remount CD

```VMID={VMID}; qm stop $VMID && qm wait $VMID && qm set $VMID -ide2 local:iso/{FILE.ISO},media=cdrom && qm set $VMID -boot order=ide2 && qm start $VMID && echo "Added Talos ISO, set boot to CD drive, and started VM $VMID"```


# Original README

<div align="center">
  <a href="#">
    <img src="https://raw.githubusercontent.com/tteck/Proxmox/main/misc/images/logo.png" height="100px" />
 </a>
</div>
<h1 align="center">Proxmox VE Helper-Scripts</h1>

<p align="center">
  <a href="https://helper-scripts.com">Website</a> | 
  <a href="https://github.com/tteck/Proxmox/blob/main/.github/CONTRIBUTING.md">Contribute</a> |
  <a href="https://github.com/tteck/Proxmox/blob/main/USER_SUBMITTED_GUIDES.md">Guides</a> |
  <a href="https://github.com/tteck/Proxmox/blob/main/CHANGELOG.md">Changelog</a> |
  <a href="https://ko-fi.com/D1D7EP4GF">Support</a>
</p>

---

> [!WARNING]
Be cautious of copycat or coat-tailing sites that exploit the project's popularity with potentially malicious intent. Please only trust information from https://Helper-Scripts.com/ or https://tteck.github.io/Proxmox/.

These scripts empower users to create a Linux container or virtual machine interactively, providing choices for both simple and advanced configurations. The basic setup adheres to default settings, while the advanced setup gives users the ability to customize these defaults. 

Options are displayed to users in a dialog box format. Once the user makes their selections, the script collects and validates their input to generate the final configuration for the container or virtual machine.
<p align="center">
Be cautious and thoroughly evaluate scripts and automation tasks obtained from external sources. <a href="https://github.com/tteck/Proxmox/blob/main/CODE-AUDIT.md">Read more</a>
</p>
<sub><div align="center"> Proxmox® is a registered trademark of Proxmox Server Solutions GmbH. </div></sub>
