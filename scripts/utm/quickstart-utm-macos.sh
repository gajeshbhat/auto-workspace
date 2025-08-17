#!/usr/bin/env bash
set -euo pipefail

# Quickstart (Phase 0) for creating a macOS VM in UTM and preparing to run Ansible.
# This script does NOT create the VM for you (UTM GUI does), but prints the exact steps and
# opens UTM. Afterwards, you will run the guest-side script to install Ansible and execute your playbook.
#
# Usage:
#   scripts/utm/quickstart-utm-macos.sh [--open]
#
# Tips:
# - Use your existing IPSW file when the UTM wizard asks for it
# - Name the VM (e.g., macos-ci)
# - Networking: NAT
# - Add a Shared Directory pointing to your repo root (Read-only is fine)
# - In new UTM versions, the share auto-mounts at: /Volumes/My Shared Files/<Your Share Name>

OPEN_UTM="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --open) OPEN_UTM="true"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

log() { echo "[+] $*"; }

cat <<'EOF'

==========================
UTM macOS VM: Phase 0 Steps
==========================
1) Launch UTM and create a new VM:
   - Click "+" > Virtualize > macOS
   - Select your IPSW file when prompted
   - Name the VM (e.g., macos-ci)
   - Assign CPU/RAM (e.g., 4 CPU, 8 GB) and a disk (e.g., 64 GB)
   - Networking: NAT
   - Sharing: Add a Shared Directory pointing to your repo root (Read-only optional)
     NOTE: New UTM auto-mounts shares under: /Volumes/My Shared Files/<Your Share Name>

2) Start the VM and complete Setup Assistant (one time only).

3) In the guest (macOS) Terminal, run the Ansible runner from the auto-mounted share path:
   a) Discover the auto-mounted path:
      - ls "/Volumes/My Shared Files"
      - cd "/Volumes/My Shared Files/<Your Share Name>"
   b) Run the guest-side script (installs Homebrew + Ansible, runs your playbook):
      - sudo bash "/Volumes/My Shared Files/<Your Share Name>/scripts/macos-guest/run-ansible.sh"

4) Rinse & repeat: After you change your repo on the host, just re-run step 3b inside the guest.

Troubleshooting:
- If you don't see your share in Finder > Computer > My Shared Files, ensure the VM Settings > Sharing has your folder added.
- If auto-mount isn't present, fall back to manual mount (may not be needed on latest UTM):
  sudo mkdir -p /Volumes/HostShare
  sudo mount -t virtiofs share /Volumes/HostShare
  Then run:
  sudo bash /Volumes/HostShare/scripts/macos-guest/run-ansible.sh

EOF

if [[ "$OPEN_UTM" == "true" ]]; then
  log "Opening UTM..."
  open -a UTM || true
fi

log "Quickstart printed. Open UTM (or re-run with --open) and follow the steps above."

