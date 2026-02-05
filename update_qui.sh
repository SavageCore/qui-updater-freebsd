#!/bin/sh
# shellcheck shell=sh

# qui Update Script for TrueNAS Core (FreeBSD)
# This script updates the qui web UI for qBittorrent

set -e

# Configuration
SERVICE_NAME="qui"
INSTALL_DIR="/usr/local/bin"
BACKUP_DIR="/root/qui_backups"
GITHUB_REPO="autobrr/qui"
SCRIPT_REPO="SavageCore/qui-updater-freebsd"
QUI_USER="quiuser"
QUI_GROUP="quiuser"
QUI_HOME="/home/quiuser"
RC_SCRIPT_PATH="/usr/local/etc/rc.d/qui"
RC_SCRIPT_URL="https://raw.githubusercontent.com/SavageCore/qui-updater-freebsd/main/rc.d/qui"
SCRIPT_VERSION="0.0.0"
QBITTORRENT_PKG="qbittorrent-nox"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Output functions
print_header() {
    printf "\n%b%b==>%b %b%s%b\n" "$BOLD" "$CYAN" "$NC" "$BOLD" "$1" "$NC"
}

log_info() {
    printf "    %b✓%b %s\n" "$GREEN" "$NC" "$1"
}

log_warn() {
    printf "    %b!%b %s\n" "$YELLOW" "$NC" "$1"
}

log_error() {
    printf "    %b✗%b %s\n" "$RED" "$NC" "$1"
}

log_detail() {
    printf "      %s\n" "$1"
}

# Print banner
BANNER_TEXT="qui Updater for TrueNAS Core (v$SCRIPT_VERSION)"
BANNER_WIDTH=$(tput cols 2>/dev/null || echo 50)
# Cap width to reasonable bounds
[ "$BANNER_WIDTH" -gt 80 ] && BANNER_WIDTH=80
[ "$BANNER_WIDTH" -lt 40 ] && BANNER_WIDTH=40
LINE=$(printf '%*s' "$BANNER_WIDTH" '' | tr ' ' '═')
PADDING=$(( (BANNER_WIDTH - ${#BANNER_TEXT}) / 2 ))
PADDED_TEXT=$(printf '%*s%s%*s' "$PADDING" '' "$BANNER_TEXT" "$PADDING" '')
# Adjust if odd length
[ "${#PADDED_TEXT}" -lt "$BANNER_WIDTH" ] && PADDED_TEXT="$PADDED_TEXT "
printf "\n%b%s%b\n" "$BOLD" "$LINE" "$NC"
printf "%b%s%b\n" "$BOLD" "$PADDED_TEXT" "$NC"
printf "%b%s%b\n" "$BOLD" "$LINE" "$NC"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    printf "\n"
    log_error "This script must be run as root"
    exit 1
fi

check_script_update() {
    print_header "Checking for script updates"
    
    # Use fetch with a 5s timeout to prevent hanging on flaky connections
    SCRIPT_JSON=$(fetch -T 5 -qo - "https://api.github.com/repos/$SCRIPT_REPO/releases/latest" 2>/dev/null)
    if [ -z "$SCRIPT_JSON" ]; then
        log_warn "Could not check for script updates (no releases found or timeout)"
        return
    fi
 
    LATEST_SCRIPT_VER=$(echo "$SCRIPT_JSON" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | sed 's/^v//')
    SCRIPT_URL=$(echo "$SCRIPT_JSON" | tr ',' '\n' | grep -i 'browser_download_url' | grep -i 'update_qui.sh' | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p' | head -1)
 
    if [ -z "$LATEST_SCRIPT_VER" ] || [ -z "$SCRIPT_URL" ]; then
        log_warn "Could not find script release asset"
        return
    fi
 
    if [ "$SCRIPT_VERSION" != "$LATEST_SCRIPT_VER" ]; then
        log_info "New script version available: $LATEST_SCRIPT_VER"
        
        # Determine current script path
        SCRIPT_PATH=$(realpath "$0" 2>/dev/null || echo "$0")
        
        # Download new version to a temp file
        TEMP_SCRIPT="/tmp/update_qui_new.sh"
        if fetch -T 5 -o "$TEMP_SCRIPT" "$SCRIPT_URL"; then
            chmod +x "$TEMP_SCRIPT"
            log_info "Applying update and restarting script..."
            
            # If we are running from /root/update_qui.sh, replace it
            if [ "$SCRIPT_PATH" = "/root/update_qui.sh" ] || [ "$SCRIPT_PATH" = "./update_qui.sh" ]; then
                mv "$TEMP_SCRIPT" "$SCRIPT_PATH"
                exec "$SCRIPT_PATH" "$@"
            else
                # If running from somewhere else (like a pipe or random dir), 
                # just exec the new one and let it handle the rest
                exec "$TEMP_SCRIPT" "$@"
            fi
        else
            log_error "Failed to download script update"
        fi
    else
        log_info "Script is up to date (v$SCRIPT_VERSION)"
    fi
}

# Function to create the quiuser if it doesn't exist
setup_user() {
    if ! id "$QUI_USER" >/dev/null 2>&1; then
        print_header "Creating $QUI_USER user"
        pw useradd "$QUI_USER" -c "qui service user" -d "$QUI_HOME" -m -s /bin/sh
        log_info "User $QUI_USER created with home $QUI_HOME"
    else
        log_info "User $QUI_USER already exists"
    fi

    # Ensure home directory exists with correct permissions
    if [ ! -d "$QUI_HOME" ]; then
        mkdir -p "$QUI_HOME"
        chown "$QUI_USER":"$QUI_GROUP" "$QUI_HOME"
        log_info "Created home directory $QUI_HOME"
    fi

    # Create .config/qui directory if it doesn't exist
    if [ ! -d "$QUI_HOME/.config/qui" ]; then
        mkdir -p "$QUI_HOME/.config/qui"
        chown -R "$QUI_USER":"$QUI_GROUP" "$QUI_HOME/.config"
        log_info "Created config directory $QUI_HOME/.config/qui"
    fi

    # Create .screen directory if it doesn't exist
    if [ ! -d "$QUI_HOME/.screen" ]; then
        mkdir -p "$QUI_HOME/.screen"
        chmod 700 "$QUI_HOME/.screen"
        chown "$QUI_USER":"$QUI_GROUP" "$QUI_HOME/.screen"
        log_info "Created screen directory $QUI_HOME/.screen"
    fi
}

# Function to install the rc.d service script
install_service() {
    # Ensure dependencies are installed
    if ! pkg info -e screen >/dev/null 2>&1; then
        print_header "Installing qui dependencies"
        pkg install -y screen
    fi

    if [ ! -f "$RC_SCRIPT_PATH" ]; then
        print_header "Installing qui service script"
        mkdir -p "$(dirname "$RC_SCRIPT_PATH")"
        if fetch -o "$RC_SCRIPT_PATH" "$RC_SCRIPT_URL"; then
            chmod +x "$RC_SCRIPT_PATH"
            log_info "Service script installed to $RC_SCRIPT_PATH"
        else
            log_error "Failed to download service script from $RC_SCRIPT_URL"
            exit 1
        fi
    fi

    # Always ensure it is enabled
    if [ -f "$RC_SCRIPT_PATH" ]; then
        if ! sysrc -qc qui_enable=YES; then
            sysrc qui_enable=YES >/dev/null 2>&1
            log_info "Enabled qui service"
        fi
        # Clear any previously set qui_command to revert to default
        if sysrc -qc qui_command; then
            sysrc -x qui_command >/dev/null 2>&1
            log_info "Reverted qui_command to default"
        fi
    fi
}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Check for script updates
check_script_update "$@"

# Setup user and service (checks within functions handle existing installs)
setup_user
install_service

# Function to handle fresh qBittorrent password capture
capture_qb_password() {
    print_header "Capturing qBittorrent Temporary Password" >&2
    
    # 1. Ensure profile directory exists and has correct ownership
    QB_PROFILE="/var/db/qbittorrent/conf"
    mkdir -p "$QB_PROFILE"
    # pkg usually creates the user, but we'll be safe
    if ! id "qbittorrent" >/dev/null 2>&1; then
        pw useradd qbittorrent -d /nonexistent -s /usr/sbin/nologin -c "qBittorrent User" >&2 || true
    fi
    chown -R qbittorrent:qbittorrent /var/db/qbittorrent

    # 2. Run qbit-nox once to get password
    log_info "Running qBittorrent-nox briefly..." >&2
    LOG_FILE="/tmp/qb_first_run.log"
    rm -f "$LOG_FILE"
    
    # Start in background, wait, then kill
    # Note: Using single quotes for the command string and double quotes inside for variable expansion
    su -m qbittorrent -c "/usr/local/bin/qbittorrent-nox --confirm-legal-notice --profile=\"$QB_PROFILE\"" > "$LOG_FILE" 2>&1 &
    QB_PID=$!
    
    # Wait for the password to appear or timeout
    count=0
    temp_pass=""
    while [ $count -lt 15 ]; do
        if grep -q "temporary password is provided for this session:" "$LOG_FILE"; then
            temp_pass=$(grep "temporary password is provided for this session:" "$LOG_FILE" | awk '{print $NF}' | tr -d '\r\n')
            break
        fi
        sleep 1
        count=$((count + 1))
    done
    
    kill $QB_PID >/dev/null 2>&1 || true
    rm -f "$LOG_FILE"
    
    if [ -n "$temp_pass" ]; then
        log_info "Temporary password captured!" >&2
        echo "$temp_pass"
    else
        log_warn "Could not capture temporary password automatically." >&2
        echo ""
    fi
}

# Function to patch qui config for external access
patch_qui_config() {
    cfg="$QUI_HOME/.config/qui/config.toml"
    if [ -f "$cfg" ]; then
        if grep -q "host = \"0.0.0.0\"" "$cfg"; then
            log_info "Host is already set to 0.0.0.0"
        else
            log_info "Setting host to 0.0.0.0..."
            if sed -i '' 's/host = "localhost"/host = "0.0.0.0"/' "$cfg" 2>/dev/null && \
               sed -i '' 's/host = "127.0.0.1"/host = "0.0.0.0"/' "$cfg" 2>/dev/null; then
                chown "$QUI_USER":"$QUI_GROUP" "$cfg"
                log_info "Successfully patched host in config.toml"
            else
                log_error "Failed to patch host in config.toml"
            fi
        fi
    else
        log_error "config.toml not found at $cfg"
    fi
}

# Function to handle service enablement and flags
enable_qbittorrent() {
    if [ -f "/usr/local/etc/rc.d/qbittorrent" ]; then
        if ! sysrc -qc qbittorrent_enable=YES; then
            sysrc qbittorrent_enable=YES >/dev/null 2>&1
            log_info "Enabled qbittorrent service"
        fi
        # Crucial: qbittorrent-nox requires legal notice confirmation to start without interaction
        if ! sysrc -qc qbittorrent_flags="--confirm-legal-notice"; then
            sysrc qbittorrent_flags="--confirm-legal-notice" >/dev/null 2>&1
            log_info "Applied qbittorrent legal notice confirmation"
        fi
    fi
}

# Ensure qbittorrent is enabled if already installed
enable_qbittorrent

# Version check functions
get_current_qui_version() {
    if [ -f "$INSTALL_DIR/qui" ]; then
        version=$("$INSTALL_DIR/qui" --version 2>/dev/null | sed -n 's/.*version \([0-9.]*\).*/\1/p')
        echo "${version:-unknown}"
    else
        echo ""
    fi
}

get_latest_qui_info() {
    LATEST_RELEASE=$(fetch -qo - "https://api.github.com/repos/$GITHUB_REPO/releases/latest")
    if [ -z "$LATEST_RELEASE" ]; then
        return 1
    fi
    VERSION=$(echo "$LATEST_RELEASE" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    DOWNLOAD_URL=$(echo "$LATEST_RELEASE" | sed -n 's/.*"browser_download_url": *"\([^"]*freebsd_x86_64\.tar\.gz[^"]*\)".*/\1/p' | head -1)
    echo "$VERSION|$DOWNLOAD_URL"
}

get_pkg_info() {
    pkg_name=$1
    # Update repo catalogue first
    pkg update -q >/dev/null 2>&1 || true
    
    current_ver=$(pkg query %v "$pkg_name" 2>/dev/null | tr -d '[:space:]')
    
    # Try multiple ways to get latest version
    latest_ver=$(pkg rquery %v "$pkg_name" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    if [ -z "$latest_ver" ]; then
        latest_ver=$(pkg search -q -Q version -e "$pkg_name" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    fi
    
    if [ -z "$current_ver" ]; then
        echo "not_installed|$latest_ver"
    else
        echo "$current_ver|$latest_ver"
    fi
}
 
print_summary_line() {
    component=$1
    current=$2
    latest=$3
    
    if [ -z "$latest" ]; then
        # If we couldn't get latest version
        if [ "$current" = "not_installed" ] || [ -z "$current" ]; then
            printf "    %-20s %b%-15s%b (Not installed, could not check repo)\n" "$component" "$RED" "Unknown" "$NC"
        else
            printf "    %-20s %b%-15s%b (Installed, could not check latest)\n" "$component" "$YELLOW" "$current" "$NC"
        fi
    elif [ "$current" = "$latest" ] || [ "v$current" = "$latest" ]; then
        printf "    %-20s %b%-15s%b (Up to date)\n" "$component" "$GREEN" "$latest" "$NC"
    elif [ -z "$current" ] || [ "$current" = "not_installed" ]; then
        printf "    %-20s %b%-15s%b (Not installed -> %s)\n" "$component" "$YELLOW" "fresh install" "$NC" "$latest"
    else
        printf "    %-20s %b%-15s%b -> %b%s%b\n" "$component" "$YELLOW" "$current" "$NC" "$GREEN" "$latest" "$NC"
    fi
}

# Main Execution Logic Starts Here
QUI_CURRENT=$(get_current_qui_version)
QUI_INFO=$(get_latest_qui_info || echo "|")
QUI_LATEST=$(echo "$QUI_INFO" | cut -d'|' -f1)
QUI_URL=$(echo "$QUI_INFO" | cut -d'|' -f2)

QB_INFO=$(get_pkg_info "$QBITTORRENT_PKG")
QB_CURRENT=$(echo "$QB_INFO" | cut -d'|' -f1)
QB_LATEST=$(echo "$QB_INFO" | cut -d'|' -f2)

print_header "Checking for updates"
print_summary_line "qui" "$QUI_CURRENT" "$QUI_LATEST"
print_summary_line "qbittorrent-nox" "$QB_CURRENT" "$QB_LATEST"

UPDATES_NEEDED=0
QUI_UPDATE=0
QB_UPDATE=0

if [ -n "$QUI_LATEST" ] && { [ -z "$QUI_CURRENT" ] || [ "v$QUI_CURRENT" != "$QUI_LATEST" ]; }; then
    QUI_UPDATE=1
    UPDATES_NEEDED=1
fi

if [ -n "$QB_LATEST" ] && [ "$QB_CURRENT" != "$QB_LATEST" ]; then
    QB_UPDATE=1
    UPDATES_NEEDED=1
fi

if [ "$UPDATES_NEEDED" -eq 0 ]; then
    printf "\n%b%bEverything is up to date!%b\n\n" "$GREEN" "$BOLD" "$NC"
    exit 0
fi

# Perform Updates
if [ "$QB_UPDATE" -eq 1 ]; then
    print_header "Updating qbittorrent-nox"
    if [ "$QB_CURRENT" = "not_installed" ]; then
        log_info "Installing $QBITTORRENT_PKG..."
        pkg install -y "$QBITTORRENT_PKG"
        
        # Capture password on first run
        QB_TEMP_PASS=$(capture_qb_password)
        
        # Enable it immediately after installation
        enable_qbittorrent
    else
        log_info "Upgrading $QBITTORRENT_PKG ($QB_CURRENT -> $QB_LATEST)..."
        pkg upgrade -y "$QBITTORRENT_PKG"
    fi
    
    # Ensure it's started after update/install
    if [ -f "/usr/local/etc/rc.d/qbittorrent" ]; then
        log_info "Starting qbittorrent service..."
        # On FreeBSD, qbittorrent-nox might need a user to be created or specified
        # We try to start it. If it fails, we check for a common culprit: missing user
        if ! service qbittorrent status >/dev/null 2>&1; then
            service qbittorrent start >/dev/null 2>&1 || true
        fi
        
        sleep 3
        if service qbittorrent status >/dev/null 2>&1; then
            log_info "qbittorrent service is running"
        else
            log_warn "qbittorrent service failed to start"
            log_detail "Check /var/log/messages or try: service qbittorrent onestart"
        fi
    fi
fi


if [ "$QUI_UPDATE" -eq 1 ]; then
    VERSION="$QUI_LATEST"
    DOWNLOAD_URL="$QUI_URL"
    CURRENT_VERSION="$QUI_CURRENT"
    
    if [ -z "$CURRENT_VERSION" ]; then
        log_warn "qui not found - performing fresh installation"
    fi

    # Stop the qui service if it's running
    if service "$SERVICE_NAME" status >/dev/null 2>&1; then
        print_header "Stopping $SERVICE_NAME service"
        if service "$SERVICE_NAME" stop >/dev/null 2>&1; then
            log_info "Service stopped"
        else
            log_error "Failed to stop service"
            exit 1
        fi
    fi

    # Backup current version
    if [ -f "$INSTALL_DIR/qui" ]; then
        print_header "Creating backup"
        BACKUP_FILE="$BACKUP_DIR/qui_$(date +%Y%m%d_%H%M%S)"
        cp "$INSTALL_DIR/qui" "$BACKUP_FILE"
        log_info "Backup saved to $BACKUP_FILE"
    fi

    # Download new version
    print_header "Downloading qui $VERSION"

    TEMP_FILE="/tmp/qui_${VERSION}.tar.gz"
    rm -f "$TEMP_FILE"

    FETCH_STATUS=0
    FETCH_OUTPUT=$(fetch -o "$TEMP_FILE" "$DOWNLOAD_URL" 2>&1) || FETCH_STATUS=$?

    if [ "$FETCH_STATUS" -ne 0 ]; then
        log_error "Download failed (exit code: $FETCH_STATUS)"
        log_detail "$FETCH_OUTPUT"
        service "$SERVICE_NAME" start 2>/dev/null || true
        exit 1
    fi

    if [ ! -f "$TEMP_FILE" ]; then
        log_error "Download file not found"
        service "$SERVICE_NAME" start 2>/dev/null || true
        exit 1
    fi

    FILE_SIZE=$(du -h "$TEMP_FILE" | cut -f1)
    log_info "Downloaded ($FILE_SIZE)"

    # Extract and install
    print_header "Installing qui"

    TEMP_DIR="/tmp/qui_extract_$$"
    mkdir -p "$TEMP_DIR"

    # Extract only the qui binary from the archive
    if ! tar -xzf "$TEMP_FILE" -C "$TEMP_DIR" --include='*/qui' --include='qui' 2>/dev/null && \
        ! tar -xzf "$TEMP_FILE" -C "$TEMP_DIR" --wildcards '*/qui' 'qui' 2>/dev/null; then
        # Fallback: extract everything if selective extraction fails
        if ! tar -xzf "$TEMP_FILE" -C "$TEMP_DIR"; then
            log_error "Failed to extract archive"
            rm -rf "$TEMP_DIR" "$TEMP_FILE"
            service "$SERVICE_NAME" start 2>/dev/null || true
            exit 1
        fi
    fi

    QUI_BINARY=$(find "$TEMP_DIR" -name "qui" -type f | head -1)
    if [ -z "$QUI_BINARY" ]; then
        log_error "Could not find qui binary in archive"
        rm -rf "$TEMP_DIR" "$TEMP_FILE"
        service "$SERVICE_NAME" start 2>/dev/null || true
        exit 1
    fi

    mv "$QUI_BINARY" "$INSTALL_DIR/qui"
    chmod +x "$INSTALL_DIR/qui"
    chown "$QUI_USER":"$QUI_GROUP" "$INSTALL_DIR/qui"
    rm -rf "$TEMP_DIR" "$TEMP_FILE"

    log_info "Installed to $INSTALL_DIR/qui"

    # Ensure config exists and is patched
    cfg_file="$QUI_HOME/.config/qui/config.toml"
    if [ ! -f "$cfg_file" ]; then
        print_header "Generating initial qui config"
        GEN_LOG="/tmp/qui_gen.log"
        rm -f "$GEN_LOG"
        
        # su -l (login shell) is CRITICAL to ensure $HOME is set correctly to quiuser's home
        su -l "$QUI_USER" -c "\"$INSTALL_DIR/qui\" serve" > "$GEN_LOG" 2>&1 &
        QUI_PID=$!
        log_info "Background qui process started (PID: $QUI_PID), polling for $cfg_file..."
        
        # Poll for file creation
        count=0
        while [ $count -lt 20 ]; do
            if [ -f "$cfg_file" ]; then
                log_info "Config file detected after $((count / 2)) seconds"
                break
            fi
            sleep 0.5
            count=$((count + 1))
        done
        
        if [ ! -f "$cfg_file" ]; then
            log_error "Config file was not generated within 10 seconds."
            log_detail "Last 3 lines of output from qui:"
            tail -n 3 "$GEN_LOG" | while IFS= read -r line; do log_detail "  $line"; done
        fi
        
        kill $QUI_PID >/dev/null 2>&1 || true
        rm -f "$GEN_LOG"
    fi
    patch_qui_config

    # Start the qui service
    print_header "Starting $SERVICE_NAME service"

    # Try to start and capture errors if it fails
    if START_ERROR=$(service "$SERVICE_NAME" start 2>&1); then
        log_info "Service start command sent"
    else
        log_error "Failed to start service"
        log_detail "$START_ERROR"
        exit 1
    fi

    # Verify service is running
    sleep 3
    if service "$SERVICE_NAME" status >/dev/null 2>&1; then
        log_info "Service is running"
    else
        log_error "Service is not running - check logs for issues"
        # If it failed, show why
        service "$SERVICE_NAME" status 2>&1 | while IFS= read -r line; do log_detail "$line"; done
        exit 1
    fi

    # Clean up old backups (keep last 5) - FreeBSD compatible
    BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name "qui_*" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$BACKUP_COUNT" -gt 5 ]; then
        find "$BACKUP_DIR" -maxdepth 1 -name "qui_*" -type f -print0 2>/dev/null | \
            xargs -0 stat -f '%m %N' | \
            sort -rn | \
            tail -n +6 | \
            cut -d' ' -f2- | \
            xargs rm -f 2>/dev/null || true
    fi
fi


# Success message
SUCCESS_TEXT="Update completed successfully!"
SUCCESS_PADDING=$(( (BANNER_WIDTH - ${#SUCCESS_TEXT}) / 2 ))
SUCCESS_PADDED=$(printf '%*s%s%*s' "$SUCCESS_PADDING" '' "$SUCCESS_TEXT" "$SUCCESS_PADDING" '')
[ "${#SUCCESS_PADDED}" -lt "$BANNER_WIDTH" ] && SUCCESS_PADDED="$SUCCESS_PADDED "
printf "\n%b%b%s%b\n" "$GREEN" "$BOLD" "$LINE" "$NC"
printf "%b%b%s%b\n" "$GREEN" "$BOLD" "$SUCCESS_PADDED" "$NC"
printf "%b%b%s%b\n" "$GREEN" "$BOLD" "$LINE" "$NC"

if [ "$QUI_UPDATE" -eq 1 ]; then
    printf "    qui is now running             %b%s%b\n" "$BOLD" "$QUI_LATEST" "$NC"
    printf "    Access tip: Ensure %bhost = \"0.0.0.0\"%b in %b$QUI_HOME/.config/qui/config.toml%b\n" "$CYAN" "$NC" "$CYAN" "$NC"
fi
if [ "$QB_UPDATE" -eq 1 ]; then
    printf "    qbittorrent-nox is now running %b%s%b\n" "$BOLD" "$QB_LATEST" "$NC"
    if [ -n "$QB_TEMP_PASS" ]; then
        printf "    Temporary login: %b%s%b / %b%s%b\n" "$BOLD" "admin" "$NC" "$CYAN" "$QB_TEMP_PASS" "$NC"
    else
        printf "    Note: Check logs/console for temp password if this is a fresh install.\n"
    fi
    printf "    Reset tip: Delete 'WebUI\\\\Password_PBKDF2' from qBittorrent.conf and restart.\n"
fi
printf "\n"


exit 0
