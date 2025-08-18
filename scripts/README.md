# Scripts Directory

This directory contains various utility scripts for testing and managing the auto-workspace project.

## Directory Structure

### `testing/`
Scripts for testing playbooks in isolated environments:

- **`test-linux-playbook.sh`** - Test Linux playbooks in a clean Ubuntu 24.04 VM using Multipass
  - Launches a fresh VM with configurable resources
  - Copies the repository into the VM
  - Installs Ansible and runs the Linux playbook
  - Optionally keeps or deletes the VM when finished

### `vm-setup/`
Scripts for setting up and managing virtual machines:

#### `vm-setup/utm/`
- **`quickstart-utm-macos.sh`** - UTM setup helper for macOS VM testing

#### `vm-setup/macos-guest/`
- **`run-ansible.sh`** - Run Ansible playbooks inside macOS VMs

## Usage Examples

### Testing Linux Playbook
```bash
# Basic test (auto-deletes VM after run)
./scripts/testing/test-linux-playbook.sh

# Keep VM and enable verbose logs
./scripts/testing/test-linux-playbook.sh -k -v

# Custom resources
./scripts/testing/test-linux-playbook.sh -n my-test -c 4 -m 8G -d 30G
```

### macOS VM Testing
```bash
# Setup UTM for macOS testing
./scripts/vm-setup/utm/quickstart-utm-macos.sh --open

# Run Ansible inside macOS VM (from within the VM)
sudo bash "/Volumes/My Shared Files/auto-workspace/scripts/vm-setup/macos-guest/run-ansible.sh"
```

## Migration Notes

The following files have been moved and renamed:
- `test-isolated-playbook.sh` → `testing/test-linux-playbook.sh`
- `utm/` → `vm-setup/utm/`
- `macos-guest/` → `vm-setup/macos-guest/`

This reorganization provides better categorization and makes it easier to find the right script for your needs.
