## Automated Workspace Setup Ubuntu 24.04 LTS

Automated workspace setup tool for Ubuntu 24.04 LTS that configures development environments, virtualization tools, and GUI applications using Ansible. Please make sure you have atleast 8GB of RAM and 30GB of free disk space before running the script.

### Features
1. Docker + Docker Compose
2. KVM/QEMU
3. LXD + MicroK8s
4. VirtualBox + Extension Pack
5. Wine
6. Development Tools (Git, Vim, Screen, etc.)
7. GUI Applications (VS Code, Spotify, Postman, etc.)
8. Automated cleanup

### Prerequisites

1. Install Git and Ansible on Ubuntu 24.04 LTS:

```bash
sudo apt update
sudo apt install git ansible -y
```

2. Clone the repository:

```bash
git clone https://github.com/yourusername/Auto-Workspace-GUI.git
cd Auto-Workspace-GUI
```
3. Update the `ansible/linux.yml` file with your username, Git global user name, and email:

```yaml
vars:
  username: yourusername
  git_user_name: "Your Name"
  git_user_email: "your.email@example.com"
```

4. Run the playbook:

```bash
ansible-playbook -i ansible/hosts ansible/linux.yml
# use --ask-become-pass argument with the above command if you are not running as root
# Takes ~40 minutes to complete depending on your internet speed and system specifications.
```
### What Gets Installed

#### Linux (Ubuntu 24.04 LTS)
1. Virtualization: Docker, KVM, LXD, VirtualBox
2. Development: Git, Vim, Screen, Tmux, Build Tools, Rust, Android Tools (ADB/Fastboot), Dotrun, Also some of my dotfiles. But these are very lightweight and some basic configurations.
3. GUI Apps: VS Code, Spotify, Postman, VLC, LibreOffice, etc.
4. Cloud Tools: Multipass, Snapcraft, MicroK8s
5. Productivity: Zoom, Proton Pass
6. Qt Framework: Optional manual installation with install-qt.sh script

#### macOS (15.4)
1. Virtualization: Docker, VirtualBox, Multipass
2. Development: Git, Vim, Screen, Python3, Rust
3. GUI Apps: Chrome, VS Code, Spotify, VLC, Transmission, ProtonVPN
4. Productivity: iA Writer (via Mac App Store)

### Manual Qt Installation (Optional - Linux)

Qt installation requires interactive authentication and is provided as a separate script. After running the main Ansible playbook, you can optionally install Qt:

```bash
# Run the Qt installation script
bash ansible/playbooks/linux/install-qt.sh

# Or with command line arguments (to avoid interactive prompts)
bash ansible/playbooks/linux/install-qt.sh --email your-qt-account@example.com --password your-password

# Or with environment variables
QT_EMAIL=your-qt-account@example.com QT_PASSWORD=your-password bash ansible/playbooks/linux/install-qt.sh
```

**What the Qt script installs:**
- Qt 6.9.1 SDK (includes Qt Creator, CMake, Ninja)
- Automatically adds Qt to your PATH
- Privacy-respecting defaults (disables telemetry)
- Verifies installation with qmake version check

**Requirements for Qt installation:**
- Qt account (free registration at https://www.qt.io/)
- Internet connection for downloading (~2GB+ installation)
- Sufficient disk space (~10GB+ for full SDK)

Notes
 1. Currently only supports Ubuntu 24.04 LTS
 2. System reboot may be required after installation

### Post-Installation

#### After installation completes:

1. Log out and log back in to apply group changes
2. Verify installations using version check commands
3. Configure additional application settings as needed
4. The playbook handles most configurations automatically, but some applications may need additional setup through their GUIs.

### Testing with Multipass (Ubuntu 24.04)

Use the included script to test the playbooks in a clean Ubuntu 24.04 VM provisioned by Multipass.

What it does:
- Launches a fresh VM (Ubuntu 24.04)
- Copies this repository into the VM
- Installs Ansible and prerequisites
- Runs ansible/linux.yml inside the VM
- Optionally keeps or deletes the VM when finished

Requirements:
- Multipass installed on your host: https://multipass.run/
- Internet connectivity from the host and VM

Quick start:
- Make executable:
  - chmod +x scripts/testing/test-linux-playbook.sh
- Run (auto-deletes VM after run):
  - ./scripts/testing/test-linux-playbook.sh

Options:
- -n name   VM name (default: aw-test-<timestamp>)
- -c cpus   CPU count (default: 2)
- -m mem    Memory (default: 12G)
- -d disk   Disk size (default: 50G)
- -k        Keep the VM after the run (default: delete)
- -v        Verbose Ansible output (-vvv)

Examples:
- Keep VM and enable verbose logs:
  - ./scripts/testing/test-linux-playbook.sh -k -v
- Custom resources:
  - ./scripts/testing/test-linux-playbook.sh -n my-test -c 4 -m 8G -d 30G

Isolating what runs:
- This script always runs ansible/linux.yml. To limit scope, comment out unrelated import_tasks in ansible/linux.yml and keep only the entries you want to validate (e.g., install-dev-tools.yml, install-gui-apps.yml).

Sudo handling:
- The script detects if passwordless sudo is available inside the VM.
  - If passwordless: runs without prompting
  - Otherwise: runs ansible-playbook with -K (ask-become-pass). When prompted, press Enter if the VM is configured for passwordless sudo; otherwise enter the VM's sudo password.

Inspecting the VM (when keeping it):
- Open a shell: multipass shell <vm-name>
- Re-run the playbook:
  - cd ~/auto-workspace
  - ANSIBLE_STDOUT_CALLBACK=yaml ansible-playbook -i ansible/hosts ansible/linux.yml -K -vvv
- Stop/delete when done:
  - multipass stop <vm-name>
  - multipass delete <vm-name>
  - multipass purge

Troubleshooting:
- Multipass not found: install from https://multipass.run/
- VM launch failures: ensure virtualization is enabled (KVM/Hyper-V/etc.)
- Apt/network hiccups: retry; mirrors can have temporary issues
- Proton VPN repo key issues: ensure playbook uses modern signed-by keyring
- 0 A.D. PPA warnings about trusted.gpg: prefer a repo entry with an explicit signed-by keyring

Notes:
- ansible/linux.yml may reference your environment for username (e.g., lookup('env','USER')).
- Script defaults: CPUs=2, MEM=12G, DISK=50G (override with flags).

## Automated Workspace Setup for macOS 15.4

Automated workspace setup tool for macOS 15.4 that configures development environments and applications using Ansible. Please make sure you have at least 16GB of RAM and 60GB of free disk space before running the script.

**🧪 Testing:** Use the included UTM scripts to test in a macOS VM - see [Testing with UTM](#testing-with-utm-macos-virtual-machine) section below.

### Features
1. Docker + Docker CLI
2. VirtualBox + Multipass
3. Development Tools (Git, Vim, Screen, Python3, Rust, pipx, Dotrun)
4. GUI Applications (Chrome, VS Code, Spotify, VLC)
5. Productivity Tools (Adobe Reader, ProtonVPN)
6. Package Manager (Homebrew)
7. Command Line Tools (Xcode)
8. Qt Framework (optional manual installation)
9. Automated cleanup

## Prerequisites
1. Install [Homebrew](https://brew.sh/). You can run the following command in your terminal:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
Press `Enter` to continue and follow the prompts. Please make sure to run the following commands (or similar commands that the brew installer outputs) after the installation is complete to add Homebrew to your PATH:
```bash
echo >> /Users/gajesh/.zprofile
echo 'eval "$(/usr/local/bin/brew shellenv)"' >> /Users/gajesh/.zprofile
eval "$(/usr/local/bin/brew shellenv)"
```

2. Install [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html). You can run the following command in your terminal:
```bash
brew install ansible
```
Check it's installed correctly:
```bash
ansible --version
```

3. Clone this repository:
```bash
git clone https://github.com/gajeshbhat/auto-workspace.git
cd auto-workspace/ansible
```

4. Update the `macos.yml` file with your Git global user name, and email:
```yaml
vars:
  git_global_user_name: "Your Name"
  git_global_user_email: "your.email@example.com"
```

**Note for VM Testing:** If you plan to test this playbook in a VM (like UTM), comment out the `mas_applications` section in `macos.yml` as Mac App Store apps require Apple ID authentication and may not work in VMs.

5. Run the playbook:
```bash
ansible-playbook macos.yml --ask-become-pass # Enter your sudo password when prompted for BECOME Password and Enter password as requested
```

To install only specific components, you can use tags:
```bash
# Install only development tools
ansible-playbook macos.yml --ask-become-pass --tags "devtools"

# Install only GUI applications
ansible-playbook macos.yml --ask-become-pass --tags "gui"
```

6. Check mode (dry run) to see what would change
```bash
ansible-playbook macos.yml --check --ask-become-pass
```

### Manual Qt Installation (Optional)

Qt installation requires interactive authentication and is provided as a separate script. After running the main Ansible playbook, you can optionally install Qt:

```bash
# Run the Qt installation script
bash ansible/playbooks/macos/install-qt.sh

# Or with command line arguments (to avoid interactive prompts)
bash ansible/playbooks/macos/install-qt.sh --email your-qt-account@example.com --password your-password

# Or with environment variables
QT_EMAIL=your-qt-account@example.com QT_PASSWORD=your-password bash ansible/playbooks/macos/install-qt.sh
```

**What the Qt script installs:**
- Qt 6.9.1 Full SDK (includes Qt Creator, CMake, Ninja)
- Automatically adds Qt to your PATH
- Privacy-respecting defaults (disables telemetry)
- Verifies installation with qmake version check

**Requirements for Qt installation:**
- Qt account (free registration at https://www.qt.io/)
- Internet connection for downloading (~2GB+ installation)
- Sufficient disk space (~10GB+ for full SDK)



### Testing with UTM (macOS Virtual Machine)

Use the included UTM scripts to test the macOS playbooks in a clean macOS VM on Apple Silicon Macs.

#### What it does:
- Creates a macOS VM using UTM with virtio-fs file sharing
- Shares your repository with the VM for live testing
- Installs prerequisites (Xcode Command Line Tools, Homebrew, Ansible)
- Runs the macOS playbook inside the VM
- Automatically skips virtualization-related packages that don't work in VMs

#### Requirements:
- **UTM** installed on your Mac: https://mac.getutm.app/
- **macOS IPSW file** for the version you want to test
  - Download from: https://ipsw.me/ (e.g., https://ipsw.me/Mac16,8 for Mac Studio)
  - Choose the macOS version that matches your testing needs
- **Apple Silicon Mac** (recommended for best performance)
- At least **8GB RAM** and **64GB free disk space** for the VM

#### Quick Start:

1. **Launch UTM setup helper:**
   ```bash
   ./scripts/vm-setup/utm/quickstart-utm-macos.sh --open
   ```

2. **Download macOS IPSW (if needed):**
   - Visit https://ipsw.me/ and select your Mac model (e.g., https://ipsw.me/Mac16,8 for Mac Studio)
   - Download the macOS version you want to test (e.g., macOS 15.4)
   - IPSW files are large (10-15GB), so ensure good internet connection

3. **Create VM in UTM GUI:**
   - Click "+" → Virtualize → macOS
   - Select your downloaded IPSW file when prompted
   - Name the VM (e.g., `macos-ci`)
   - Assign resources: 4 CPU cores, 8GB RAM, 64GB disk
   - **Networking:** NAT
   - **Sharing:** Add your repository root as a shared directory

4. **Complete macOS Setup:**
   - Start the VM and complete Setup Assistant
   - Create a user account (enable auto-login for easier testing)

5. **Run Ansible inside the VM:**
   ```bash
   # In the macOS VM Terminal:
   sudo bash "/Volumes/My Shared Files/auto-workspace/scripts/vm-setup/macos-guest/run-ansible.sh"
   ```

#### Important: Mac App Store Applications

**Before testing in a VM, you MUST comment out `mas_applications` in `ansible/macos.yml`:**

```yaml
# Comment out these lines for VM testing:
# mas_applications:
#   - { id: 775737590, name: "iA Writer" }
```

**Why?** Mac App Store applications require:
- Apple ID login
- App Store authentication
- May not work properly in VMs
- Can cause the playbook to hang or fail

#### VM-Specific Behavior:

The `run-ansible.sh` script automatically:
- Skips virtualization tools (`--skip-tags virtualization,docker,virtualbox,multipass`)
- Installs Xcode Command Line Tools
- Sets up Homebrew with proper paths
- Runs the playbook with verbose output

#### Iterative Testing:

After making changes to your playbook:
1. Save changes on your host Mac
2. Re-run the guest script (no need to restart VM):
   ```bash
   sudo bash "/Volumes/My Shared Files/auto-workspace/scripts/vm-setup/macos-guest/run-ansible.sh"
   ```

#### UTM Troubleshooting:

- **Share not visible:** Check VM Settings → Sharing has your folder added
- **Performance issues:** Ensure you're using Apple Silicon Mac with adequate RAM
- **File sharing problems:** UTM auto-mounts shares at `/Volumes/My Shared Files/`
- **Network issues:** Ensure VM networking is set to NAT mode
- **Playbook hangs:** Check if `mas_applications` are commented out
```

#### UTM Quick Reference:

| Step | Command/Action |
|------|----------------|
| 0. Download IPSW | Visit https://ipsw.me/ (e.g., https://ipsw.me/Mac16,8) |
| 1. Setup UTM | `./scripts/vm-setup/utm/quickstart-utm-macos.sh --open` |
| 2. Create VM | Use UTM GUI with downloaded IPSW + NAT networking + shared directory |
| 3. Prepare for testing | Comment out `mas_applications` in `ansible/macos.yml` |
| 4. Run in VM | `sudo bash "/Volumes/My Shared Files/auto-workspace/scripts/vm-setup/macos-guest/run-ansible.sh"` |
| 5. Re-test changes | Just re-run step 4 (no VM restart needed) |

**Pro Tip:** The UTM approach is perfect for testing your Ansible changes without affecting your main macOS system, and it closely mimics the VM test harness environment you mentioned in your requirements.
