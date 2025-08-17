#!/usr/bin/env bash
set -euo pipefail

# Test script for Qt installation on macOS
# This script tests the Qt installation process before integrating with Ansible
#
# Usage:
#   ./test-qt-install.sh                    # Interactive login prompt
#   QT_EMAIL=user@example.com QT_PASSWORD=pass ./test-qt-install.sh  # Environment variables
#   ./test-qt-install.sh --email user@example.com --password pass    # Command line args

log() { echo "[$(date '+%H:%M:%S')] $*"; }
err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }
warn() { echo "[$(date '+%H:%M:%S')] WARNING: $*" >&2; }

# Configuration
QT_INSTALLER_URL="https://download.qt.io/official_releases/online_installers/qt-online-installer-mac-x64-online.dmg"
QT_INSTALLER_DMG="/tmp/qt-online-installer-mac-x64-online.dmg"
QT_INSTALL_DIR="$HOME/Qt"
QT_PACKAGE="qt6.9.1-full"

# Authentication variables
QT_EMAIL="${QT_EMAIL:-}"
QT_PASSWORD="${QT_PASSWORD:-}"

# Cleanup function
cleanup() {
    log "Cleaning up..."
    # Try to unmount any Qt volumes
    for vol in $(ls /Volumes/ 2>/dev/null | grep -E "qt.*installer.*macOS" | grep -v " " || true); do
        log "Unmounting /Volumes/$vol"
        hdiutil detach "/Volumes/$vol" 2>/dev/null || true
    done
    # Remove downloaded DMG
    rm -f "$QT_INSTALLER_DMG"
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
    local qt_cache_file="$HOME/Library/Application Support/Qt/qtaccount.ini"
    if [[ -f "$qt_cache_file" ]]; then
        log "Found existing Qt account cache at: $qt_cache_file"
        log "You may be able to install without providing credentials"
        return 0
    else
        log "No Qt account cache found. Credentials will be required."
        return 1
    fi
}

main() {
    log "Starting Qt installation test..."

    # Parse command line arguments
    parse_args "$@"

    # Check if hdiutil is available
    if ! command -v hdiutil >/dev/null 2>&1; then
        err "hdiutil not found. This should be available on macOS by default."
        exit 1
    fi

    # Check for existing Qt account cache
    if ! check_qt_cache; then
        # Get credentials if no cache exists
        get_credentials
    fi
    
    # Check if Qt is already installed
    if [[ -d "$QT_INSTALL_DIR" && -f "$QT_INSTALL_DIR/MaintenanceTool.app/Contents/MacOS/MaintenanceTool" ]]; then
        log "Qt appears to already be installed at $QT_INSTALL_DIR"
        log "MaintenanceTool found. Skipping installation."
        exit 0
    fi
    
    # Download Qt installer if not present
    if [[ ! -f "$QT_INSTALLER_DMG" ]]; then
        log "Downloading Qt Online Installer..."
        curl -L -o "$QT_INSTALLER_DMG" "$QT_INSTALLER_URL"
        log "Download completed: $QT_INSTALLER_DMG"
    else
        log "Using existing installer: $QT_INSTALLER_DMG"
    fi
    
    # Mount the DMG
    log "Mounting Qt installer DMG..."
    hdiutil attach "$QT_INSTALLER_DMG"
    
    # Wait a moment for mount to complete
    sleep 2
    
    # Find the mounted volume
    QT_VOLUME=$(ls /Volumes/ | grep -E "qt.*installer.*macOS" | grep -v " " | head -1 || true)
    if [[ -z "$QT_VOLUME" ]]; then
        err "Could not find mounted Qt volume in /Volumes/"
        ls /Volumes/
        exit 1
    fi
    log "Found Qt volume: $QT_VOLUME"
    
    # Find the app bundle
    QT_APP_PATH="/Volumes/$QT_VOLUME/$QT_VOLUME.app"
    if [[ ! -d "$QT_APP_PATH" ]]; then
        err "Could not find Qt app bundle at: $QT_APP_PATH"
        log "Contents of /Volumes/$QT_VOLUME:"
        ls -la "/Volumes/$QT_VOLUME/"
        exit 1
    fi
    log "Found Qt app bundle: $QT_APP_PATH"
    
    # Find the executable
    QT_EXECUTABLE="$QT_APP_PATH/Contents/MacOS/$QT_VOLUME"
    if [[ ! -f "$QT_EXECUTABLE" ]]; then
        err "Could not find Qt executable at: $QT_EXECUTABLE"
        log "Contents of $QT_APP_PATH/Contents/MacOS/:"
        ls -la "$QT_APP_PATH/Contents/MacOS/"
        exit 1
    fi
    log "Found Qt executable: $QT_EXECUTABLE"
    
    # Make sure executable has proper permissions
    chmod +x "$QT_EXECUTABLE"
    
    # Test the executable
    log "Testing Qt installer executable..."
    "$QT_EXECUTABLE" --help || true
    
    # Create Qt installation directory
    mkdir -p "$QT_INSTALL_DIR"
    
    # Run the installation
    log "Starting Qt installation with package: $QT_PACKAGE"
    log "Installation directory: $QT_INSTALL_DIR"

    # Build the command with authentication if needed
    local install_cmd=(
        "$QT_EXECUTABLE"
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
    if [[ -f "$QT_INSTALL_DIR/MaintenanceTool.app/Contents/MacOS/MaintenanceTool" ]]; then
        log "Qt installation appears successful!"
        log "MaintenanceTool found at: $QT_INSTALL_DIR/MaintenanceTool.app"
        
        # Try to find qmake
        QMAKE_PATH=$(find "$QT_INSTALL_DIR" -name "qmake" -type f 2>/dev/null | head -1 || true)
        if [[ -n "$QMAKE_PATH" ]]; then
            log "Found qmake at: $QMAKE_PATH"
            "$QMAKE_PATH" --version || true
        else
            log "qmake not found, but MaintenanceTool exists"
        fi
    else
        err "Qt installation may have failed - MaintenanceTool not found"
        log "Contents of $QT_INSTALL_DIR:"
        ls -la "$QT_INSTALL_DIR/" || true
        exit 1
    fi
    
    log "Qt installation test completed successfully!"
}

# Run main function with all arguments
main "$@"
