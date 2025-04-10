## Automated Workspace Setup Ubuntu 24.04 LTS

Automated workspace setup tool for Ubuntu 24.04 LTS (macOS and Windows 11 Support coming soon) that configures development environments, virtualization tools, and GUI applications using Ansible. Please make sure you have atleast 8GB of RAM and 30GB of free disk space before running the script.

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
  git_user_email: ""
```

4. Run the playbook:

```bash
ansible-playbook -i ansible/hosts ansible/linux.yml
# use --ask-become-pass argument with the above command if you are not running as root
```
### What Gets Installed

1. Virtualization: Docker, KVM, LXD, VirtualBox
2. Development: Git, Vim, Screen, Tmux, Build Tools, Also some of my dotfiles. But these are very lightweight and some basic configurations.
3. GUI Apps: VS Code, Spotify, Postman, VLC, LibreOffice, etc.
4. Cloud Tools: Multipass, Snapcraft, MicroK8s
5. Productivity: Zoom, Skype, Bitwarden

Notes
 1. Currently only supports Ubuntu 24.04 LTS
 2. macOS and Windows support planned for future releases
 3. Some tasks require user interaction for license agreements
 4. System reboot may be required after installation

### Post-Installation

#### After installation completes:

1. Log out and log back in to apply group changes
2. Verify installations using version check commands
3. Configure additional application settings as needed
4. The playbook handles most configurations automatically, but some applications may need additional setup through their GUIs.

## Automated Workspace Setup for macOS 15.4

Automated workspace setup tool for macOS 15.4 that configures development environments and applications using Ansible. Please make sure you have at least 16GB of RAM and 60GB of free disk space before running the script.

### Features
1. Docker + Docker CLI
2. VirtualBox + Multipass
3. Development Tools (Git, Vim, Screen, Python3, Rust)
4. GUI Applications (Chrome, VS Code, Spotify, VLC)
5. Productivity Tools (Adobe Reader, ProtonVPN)
6. Package Manager (Homebrew)
7. Command Line Tools (Xcode)
8. Automated cleanup

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

5. Run the playbook:
```bash
ansible-playbook macos.yml --ask-become-pass # Enter your sudo password when prompted for BECOME Password and Enter password as requested
```

6. Check mode (dry run) to see what would change
```bash
ansible-playbook macos.yml --check --ask-become-pass
```