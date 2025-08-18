#!/usr/bin/env bash
set -euo pipefail

# Qt installation script for Linux
# This script installs Qt 6.9.1 SDK on Linux systems
#
# Usage:
#   ./install-qt.sh                    # Interactive login prompt
#   QT_EMAIL=user@example.com QT_PASSWORD=pass ./install-qt.sh  # Environment variables
#   ./install-qt.sh --email user@example.com --password pass    # Command line args

log() { echo "[$(date '+%H:%M:%S')] $*"; }
err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }
warn() { echo "[$(date '+%H:%M:%S')] WARNING: $*" >&2; }

# Configuration
QT_INSTALLER_URL="https://download.qt.io/official_releases/online_installers/qt-online-installer-linux-x64-online.run"
QT_INSTALLER_FILE="/tmp/qt-online-installer-linux-x64-online.run"
QT_INSTALL_DIR="$HOME/Qt"
QT_PACKAGE="qt6.9.1-sdk"

# Authentication variables
QT_EMAIL="${QT_EMAIL:-}"
QT_PASSWORD="${QT_PASSWORD:-}"

# Cleanup function
cleanup() {
    log "Cleaning up..."
    # Remove downloaded installer
    rm -f "$QT_INSTALLER_FILE"
}

# Set trap for cleanup
trap cleanup EXIT

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --email)
                QT_EMAIL="$2"
                shift 2
                ;;
            --password)
                QT_PASSWORD="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --email EMAIL      Qt account email"
                echo "  --password PASS    Qt account password"
                echo "  --help, -h         Show this help message"
                echo ""
                echo "Environment variables:"
                echo "  QT_EMAIL           Qt account email"
                echo "  QT_PASSWORD        Qt account password"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Interactive login"
                echo "  QT_EMAIL=user@example.com QT_PASSWORD=pass $0"
                echo "  $0 --email user@example.com --password pass"
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Secure credential input
get_credentials() {
    if [[ -z "$QT_EMAIL" ]]; then
        echo -n "Qt Account Email: "
        read -r QT_EMAIL
    fi

    if [[ -z "$QT_PASSWORD" ]]; then
        echo -n "Qt Account Password: "
        read -rs QT_PASSWORD
        echo  # New line after hidden password input
    fi

    if [[ -z "$QT_EMAIL" || -z "$QT_PASSWORD" ]]; then
        err "Both email and password are required for Qt installation"
        exit 1
    fi

    log "Using Qt account: $QT_EMAIL"
}

# Check for existing Qt account cache
check_qt_cache() {
    local qt_cache_file="$HOME/.local/share/Qt/qtaccount.ini"
    if [[ -f "$qt_cache_file" ]]; then
        log "Found existing Qt account cache at: $qt_cache_file"
        log "You may be able to install without providing credentials"
        return 0
    else
        log "No Qt account cache found. Credentials will be required."
        return 1
    fi
}

# Check for required dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for required packages
    for cmd in curl chmod; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        err "Missing required dependencies: ${missing_deps[*]}"
        log "Please install them using your package manager:"
        log "  Ubuntu/Debian: sudo apt-get install curl"
        log "  RHEL/CentOS/Fedora: sudo yum install curl (or dnf)"
        exit 1
    fi
}

main() {
    log "Starting Qt installation for Linux..."

    # Parse command line arguments
    parse_args "$@"

    # Check dependencies
    check_dependencies

    # Check for existing Qt account cache
    if ! check_qt_cache; then
        # Get credentials if no cache exists
        get_credentials
    fi
    
    # Check if Qt is already installed
    if [[ -d "$QT_INSTALL_DIR" && -f "$QT_INSTALL_DIR/MaintenanceTool" ]]; then
        log "Qt appears to already be installed at $QT_INSTALL_DIR"
        log "MaintenanceTool found. Skipping installation."
        exit 0
    fi
    
    # Download Qt installer if not present
    if [[ ! -f "$QT_INSTALLER_FILE" ]]; then
        log "Downloading Qt Online Installer for Linux..."
        curl -L -o "$QT_INSTALLER_FILE" "$QT_INSTALLER_URL"
        log "Download completed: $QT_INSTALLER_FILE"
    else
        log "Using existing installer: $QT_INSTALLER_FILE"
    fi
    
    # Make installer executable
    chmod +x "$QT_INSTALLER_FILE"
    
    # Test the executable
    log "Testing Qt installer executable..."
    "$QT_INSTALLER_FILE" --help || true
    
    # Create Qt installation directory
    mkdir -p "$QT_INSTALL_DIR"
    
    # Run the installation
    log "Starting Qt installation with package: $QT_PACKAGE"
    log "Installation directory: $QT_INSTALL_DIR"

    # Build the command with authentication if needed
    local install_cmd=(
        "$QT_INSTALLER_FILE"
        --root "$QT_INSTALL_DIR"
        --accept-licenses
        --accept-obligations
        --default-answer
        --auto-answer "telemetry-question=No,AssociateCommonFiletypes=Yes"
        --confirm-command
    )

    # Add authentication if credentials are provided
    if [[ -n "$QT_EMAIL" && -n "$QT_PASSWORD" ]]; then
        install_cmd+=(--email "$QT_EMAIL" --pw "$QT_PASSWORD")
        log "Using provided Qt account credentials"
    else
        log "Attempting installation with cached credentials"
    fi

    install_cmd+=(install "$QT_PACKAGE")

    log "Running Qt installation..."
    log "Command: ${install_cmd[0]} --root ... [credentials hidden] ... install $QT_PACKAGE"

    "${install_cmd[@]}"
    
    # Check if installation was successful
    if [[ -f "$QT_INSTALL_DIR/MaintenanceTool" ]]; then
        log "Qt installation appears successful!"
        log "MaintenanceTool found at: $QT_INSTALL_DIR/MaintenanceTool"
        
        # Try to find qmake
        QMAKE_PATH=$(find "$QT_INSTALL_DIR" -name "qmake" -type f 2>/dev/null | head -1 || true)
        if [[ -n "$QMAKE_PATH" ]]; then
            log "Found qmake at: $QMAKE_PATH"
            "$QMAKE_PATH" --version || true
            
            # Add Qt to PATH in .bashrc if not already present
            if ! grep -q "Qt.*bin" "$HOME/.bashrc" 2>/dev/null; then
                log "Adding Qt to PATH in .bashrc"
                echo "" >> "$HOME/.bashrc"
                echo "# Qt installation" >> "$HOME/.bashrc"
                echo "export PATH=\"$(dirname "$QMAKE_PATH"):\$PATH\"" >> "$HOME/.bashrc"
                log "Qt added to PATH. Please run 'source ~/.bashrc' or restart your terminal."
            fi
        else
            log "qmake not found, but MaintenanceTool exists"
        fi
    else
        err "Qt installation may have failed - MaintenanceTool not found"
        log "Contents of $QT_INSTALL_DIR:"
        ls -la "$QT_INSTALL_DIR/" || true
        exit 1
    fi
    
    log "Qt installation completed successfully!"
}

# Run main function with all arguments
main "$@"
