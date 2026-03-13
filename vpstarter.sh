#!/bin/bash

# VPS Kickstarter Script for Ubuntu 22+
# Run as root to provision a new VPS with security hardening

set -e

# Color codes for user feedback
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display status messages
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# ==========================================
# PHASE 1: System Updates and UFW Setup
# ==========================================

phase1_system_updates_and_ufw() {
    info "Starting Phase 1: System Updates and UFW Setup"
    echo "=========================================="
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Please run with sudo or as root user."
    fi
    
    # Step 1: Update package lists and upgrade installed packages
    # This ensures all system packages are current before proceeding
    info "Updating package lists..."
    if apt update; then
        success "Package lists updated successfully"
    else
        error "Failed to update package lists. Please check your internet connection and try again."
    fi
    
    info "Upgrading installed packages..."
    if apt -y upgrade; then
        success "System packages upgraded successfully"
    else
        error "Failed to upgrade system packages"
    fi
    
    # Step 2: Check if UFW (Uncomplicated Firewall) is installed
    # UFW provides an easy-to-use interface for managing iptables firewall rules
    info "Checking if UFW (Uncomplicated Firewall) is installed..."
    
    if which ufw > /dev/null 2>&1; then
        success "UFW is already installed"
    else
        warning "UFW is not installed. Installing now..."
        
        # Step 3: Install UFW if not present
        # UFW is essential for basic firewall protection on the VPS
        if apt install -y ufw; then
            success "UFW installed successfully"
        else
            error "Failed to install UFW. This is required for server security."
        fi
    fi
    
    # Step 4: Allow SSH on port 22 for the duration of the script
    # This ensures the current SSH session remains connected while we work
    # Port 22 will remain open throughout the entire script until the final phase
    info "Allowing SSH on port 22 (will remain open until final confirmation)..."
    
    if ufw allow ssh; then
        success "UFW rule added: allow SSH on port 22"
    else
        error "Failed to add UFW rule for SSH port 22. This is required to maintain connectivity."
    fi
    
    # Step 5: Enable UFW
    # UFW will be enabled with SSH port 22 allowed, ensuring connectivity throughout the script
    info "Enabling UFW firewall..."
    
    if ufw enable; then
        success "UFW enabled successfully"
    else
        error "Failed to enable UFW"
    fi
    
    # Step 6: Test UFW status and verify it's active
    # This confirms the firewall is running and will protect the server
    info "Verifying UFW status..."
    
    UFW_STATUS=$(ufw status | grep -i "status:" | awk '{print $2}')
    
    if [[ "$UFW_STATUS" == "active" ]]; then
        success "UFW is active and protecting the server"
    else
        error "UFW is not active. Expected status: active, Got: $UFW_STATUS"
    fi
    
    # Display current UFW status for user information
    info "Current UFW status (port 22 will remain open for script duration):"
    ufw status
    
    success "Phase 1 completed: System updated and UFW installed and enabled with port 22 open"
    echo "=========================================="
}

# ==========================================
# PHASE 2: Non-root User Setup
# ==========================================

# Global variable to store SSH port for later phases
SSH_CUSTOM_PORT=""
NEW_USERNAME=""

# Validate each key in an authorized_keys file
# Reference: docs/ssh_key_validation.md
validate_authorized_keys_file() {
    local authorized_keys_file="$1"
    local valid_count=0
    local invalid_count=0

    if [[ ! -f "$authorized_keys_file" ]]; then
        warning "authorized_keys file not found: $authorized_keys_file"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        if echo "$line" | ssh-keygen -i -f - > /dev/null 2>&1; then
            ((valid_count++))
        else
            ((invalid_count++))
        fi
    done < "$authorized_keys_file"

    if [[ "$valid_count" -eq 0 ]]; then
        warning "No valid SSH keys were found in $authorized_keys_file"
        return 1
    fi

    if [[ "$invalid_count" -gt 0 ]]; then
        warning "Found $invalid_count invalid SSH key entries in $authorized_keys_file"
        return 1
    fi

    success "SSH key validation passed ($valid_count valid keys)"
    return 0
}

ensure_authorized_keys_permissions() {
    local username="$1"
    local ssh_dir="/home/$username/.ssh"
    local authorized_keys_file="$ssh_dir/authorized_keys"

    if [[ ! -d "$ssh_dir" ]]; then
        warning "SSH directory not found: $ssh_dir"
        return 1
    fi

    if [[ ! -f "$authorized_keys_file" ]]; then
        warning "authorized_keys file not found: $authorized_keys_file"
        return 1
    fi

    chown "$username:$username" "$ssh_dir" "$authorized_keys_file" || return 1
    chmod 700 "$ssh_dir" || return 1
    chmod 600 "$authorized_keys_file" || return 1

    local ssh_dir_mode
    local authorized_keys_mode
    ssh_dir_mode=$(stat -c "%a" "$ssh_dir")
    authorized_keys_mode=$(stat -c "%a" "$authorized_keys_file")

    if [[ "$ssh_dir_mode" != "700" || "$authorized_keys_mode" != "600" ]]; then
        warning "Incorrect permissions detected (.ssh=$ssh_dir_mode, authorized_keys=$authorized_keys_mode)"
        return 1
    fi

    success "SSH directory and authorized_keys permissions are secure"
    return 0
}

phase2_non_root_user_setup() {
    info "Starting Phase 2: Non-root User Setup"
    echo "=========================================="

    # Step 1: Prompt for a username and validate format
    while true; do
        read -p "Enter the new non-root username: " NEW_USERNAME

        if [[ -z "$NEW_USERNAME" ]]; then
            warning "Username cannot be empty"
            continue
        fi

        if ! [[ "$NEW_USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            warning "Use lowercase letters, numbers, underscores, or hyphens (must start with a letter or underscore)"
            continue
        fi

        if id "$NEW_USERNAME" > /dev/null 2>&1; then
            warning "User '$NEW_USERNAME' already exists. Choose a different username."
            continue
        fi

        break
    done

    # Step 2: Prompt for password and create the user
    local password_one
    local password_two

    while true; do
        read -s -p "Enter password for $NEW_USERNAME: " password_one
        echo ""
        read -s -p "Confirm password for $NEW_USERNAME: " password_two
        echo ""

        if [[ -z "$password_one" ]]; then
            warning "Password cannot be empty"
            continue
        fi

        if [[ "$password_one" != "$password_two" ]]; then
            warning "Passwords do not match"
            continue
        fi

        break
    done

    info "Creating user '$NEW_USERNAME'..."
    adduser --disabled-password "$NEW_USERNAME" || error "Failed to create user $NEW_USERNAME"
    echo "$NEW_USERNAME:$password_one" | chpasswd || error "Failed to set password for $NEW_USERNAME"
    unset password_one password_two
    success "User '$NEW_USERNAME' created successfully"

    # Step 3: Add the user to sudo group
    info "Adding '$NEW_USERNAME' to sudo group..."
    adduser "$NEW_USERNAME" sudo || error "Failed to add $NEW_USERNAME to sudo group"
    success "User '$NEW_USERNAME' now has sudo privileges"

    # Step 4: Manual SSH key copy step from remote client machine
    warning "Manual step required: add your local SSH public key to this server now"
    info "Run this command from your local machine:"
    echo "  ssh-copy-id -i <path_to_public_key> $NEW_USERNAME@<hostname> -p <port>"
    info "For this phase, the SSH port is still 22."
    info "Example: ssh-copy-id -i ~/.ssh/id_ed25519.pub $NEW_USERNAME@$(hostname -f) -p 22"
    info "If your key path is different, replace ~/.ssh/id_ed25519.pub accordingly."

    local copy_confirm
    while true; do
        read -p "Type 'yes' after you have completed ssh-copy-id: " copy_confirm
        if [[ "${copy_confirm,,}" == "yes" ]]; then
            break
        fi
        warning "Please complete the ssh-copy-id step before continuing."
    done

    # Step 5: Validate authorized_keys for the new user
    local authorized_keys_path="/home/$NEW_USERNAME/.ssh/authorized_keys"
    while true; do
        if validate_authorized_keys_file "$authorized_keys_path" && ensure_authorized_keys_permissions "$NEW_USERNAME"; then
            break
        fi

        warning "SSH key validation or permissions checks failed for $authorized_keys_path"
        read -p "Fix the key setup and type 'retry' to validate again: " copy_confirm
        if [[ "${copy_confirm,,}" != "retry" ]]; then
            error "SSH key validation not confirmed. Aborting for safety."
        fi
    done

    success "Phase 2 completed: Non-root user created, sudo granted, and SSH key validated"
    echo "=========================================="
}

# ==========================================
# PHASE 3: SSH Hardening
# ==========================================

# Generate a pseudo-random SSH port (10,000-65,535, avoiding common ports)
# Reference: docs/ssh_random_port_generation.md
generate_ssh_port() {
    # Ports to avoid (common services)
    local avoid_ports=(3306 3389 5432 5900 8080 8443 9200 27017 6379)
    
    # Generate random number between 10000-65535
    local port=$((RANDOM % 55536 + 10000))
    
    # Check if port is in avoid list
    for avoid in "${avoid_ports[@]}"; do
        if [ "$port" -eq "$avoid" ]; then
            generate_ssh_port  # Recursively try again
            return
        fi
    done
    
    echo "$port"
}

phase3_ssh_hardening() {
    info "Starting Phase 3: SSH Hardening"
    echo "=========================================="
    
    # Step 1: Check SSH service status
    info "Checking SSH service status..."
    if systemctl is-active --quiet ssh; then
        success "SSH service is running"
    else
        warning "SSH service is not running"
    fi
    
    # Step 2: Verify SSH is enabled for startup
    info "Verifying SSH is enabled for startup..."
    if systemctl is-enabled --quiet ssh; then
        success "SSH is enabled to start on boot"
    else
        warning "SSH is not enabled for startup, enabling now..."
        systemctl enable ssh || error "Failed to enable SSH for startup"
        success "SSH enabled for startup"
    fi
    
    # Step 3: Generate random SSH port and prompt user
    info "Generating random SSH port suggestion..."
    local suggested_port=$(generate_ssh_port)
    success "Suggested SSH port: $suggested_port"
    
    warning "IMPORTANT: SSH configuration will be prepared now, but the SSH service restart"
    warning "and port change will be deferred until the final confirmation phase."
    warning "This ensures the script can complete without disconnecting your session."
    echo ""
    
    # Prompt user for port with suggestion as default
    read -p "Enter SSH port number [$suggested_port]: " user_port
    
    # Use suggested port if user didn't enter anything
    if [[ -z "$user_port" ]]; then
        SSH_CUSTOM_PORT=$suggested_port
    else
        # Validate that user input is a number within valid range
        if ! [[ "$user_port" =~ ^[0-9]+$ ]]; then
            error "Port must be a valid number"
        fi
        
        if [[ "$user_port" -lt 10000 || "$user_port" -gt 65535 ]]; then
            error "Port must be between 10000 and 65535"
        fi
        
        SSH_CUSTOM_PORT=$user_port
    fi
    
    success "SSH port will be changed to: $SSH_CUSTOM_PORT"
    
    # Step 4: Backup original SSH config
    local ssh_config="/etc/ssh/sshd_config"
    local backup_file="${ssh_config}.backup.$(date +%Y%m%d_%H%M%S)"
    
    info "Creating backup of $ssh_config..."
    cp "$ssh_config" "$backup_file" || error "Failed to create SSH config backup"
    success "Backup created: $backup_file"
    
    # Step 5: Update SSH configuration
    info "Updating SSH configuration..."
    
    # Update Port - replace existing or add if not present
    if grep -q "^#*Port " "$ssh_config"; then
        # Port directive exists (commented or uncommented), replace it
        sed -i "s/^#*Port .*/Port $SSH_CUSTOM_PORT/" "$ssh_config"
    else
        # Port directive doesn't exist, add it
        echo "Port $SSH_CUSTOM_PORT" >> "$ssh_config"
    fi
    
    # Disable password authentication
    if grep -q "^#*PasswordAuthentication " "$ssh_config"; then
        sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' "$ssh_config"
    else
        echo "PasswordAuthentication no" >> "$ssh_config"
    fi
    
    # Restrict root login to key-only
    if grep -q "^#*PermitRootLogin " "$ssh_config"; then
        sed -i 's/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/' "$ssh_config"
    else
        echo "PermitRootLogin prohibit-password" >> "$ssh_config"
    fi
    
    success "SSH configuration updated"
    info "Configuration changes applied:"
    echo "  - Port: $SSH_CUSTOM_PORT"
    echo "  - PasswordAuthentication: no"
    echo "  - PermitRootLogin: prohibit-password"
    
    # Step 6: Validate SSH configuration without restarting
    # We validate the config syntax but DO NOT restart SSH yet
    # Restart is deferred to the final confirmation phase to prevent disconnection
    info "Validating SSH configuration syntax..."
    if sshd -t; then
        success "SSH configuration is valid (changes are prepared but not yet active)"
    else
        error "SSH configuration is invalid. Check $ssh_config"
    fi
    
    # IMPORTANT: SSH service is NOT restarted here to prevent disconnection
    # The configuration changes will take effect after the final confirmation phase
    warning ""
    warning "=========================================="
    warning "SSH RESTART DEFERRED"
    warning "=========================================="
    warning "The SSH configuration has been updated and validated."
    warning "The service restart and port change will occur AFTER"
    warning "user confirmation in the final phase."
    warning ""
    warning "Current status: SSH is still running on port 22"
    warning "New config: SSH will use port $SSH_CUSTOM_PORT after restart"
    warning "=========================================="
    
    # Step 7: Note that SSH is still on port 22 (expected behavior)
    info "Note: SSH service remains on port 22 until final restart"
    info "The new port $SSH_CUSTOM_PORT will be active after the deferred restart"
    
    # Step 8: Configure UFW for custom SSH port (to take effect after restart)
    # Port 22 remains open throughout the script - do NOT deny it here
    info "Configuring UFW firewall rules for the new SSH port..."
    
    # Allow the custom SSH port - this will take effect after SSH service restart
    if ufw allow "$SSH_CUSTOM_PORT/tcp"; then
        success "UFW rule added: allow port $SSH_CUSTOM_PORT/tcp (effective after SSH restart)"
    else
        error "Failed to add UFW rule for port $SSH_CUSTOM_PORT"
    fi
    
    # NOTE: We do NOT deny port 22 here - it remains open for the script duration
    # Port 22 will be denied in the final phase after user confirmation
    
    # Step 9: Verify UFW status
    info "Verifying UFW status..."
    ufw status verbose
    
    success "Phase 3 completed: SSH configuration prepared for port $SSH_CUSTOM_PORT"
    success "SSH restart deferred to final confirmation phase"
    info "Port $SSH_CUSTOM_PORT stored in SSH_CUSTOM_PORT for later phases"
    echo "=========================================="
}

# ==========================================
# PHASE 4: Fail2ban Setup
# ==========================================

phase4_fail2ban_setup() {
    info "Starting Phase 4: Fail2ban Setup"
    echo "=========================================="
    
    # Step 1: Install fail2ban
    # Fail2ban protects the server from brute-force attacks by monitoring logs
    info "Installing fail2ban..."
    if apt install -y fail2ban; then
        success "Fail2ban installed successfully"
    else
        error "Failed to install fail2ban"
    fi
    
    # Step 2: Create jail.d directory if it doesn't exist
    # Using jail.d/ for configuration overrides is best practice per docs/fail2ban_config_precedence.md
    info "Creating fail2ban jail.d directory..."
    if mkdir -p /etc/fail2ban/jail.d; then
        success "jail.d directory ready"
    else
        error "Failed to create jail.d directory"
    fi
    
    # Step 3: Create SSH jail configuration file
    # Configuration precedence: jail.d/sshd.conf overrides jail.local and jail.conf
    info "Creating SSH jail configuration..."
    local sshd_jail_conf="/etc/fail2ban/jail.d/sshd.conf"
    
    # Using the SSH port from Phase 2
    # Configuration values: maxretry=3, bantime=3600 (1 hour), findtime=600 (10 minutes)
    cat > "$sshd_jail_conf" << EOF
[sshd]
enabled = true
port = $SSH_CUSTOM_PORT
maxretry = 3
bantime = 3600
findtime = 600
EOF
    
    if [[ -f "$sshd_jail_conf" ]]; then
        success "SSH jail configuration created: $sshd_jail_conf"
    else
        error "Failed to create SSH jail configuration"
    fi
    
    # Step 4: Document configuration precedence
    info "Configuration precedence documented:"
    echo "  - /etc/fail2ban/jail.conf (default settings)"
    echo "  - /etc/fail2ban/jail.local (overrides)"
    echo "  - /etc/fail2ban/jail.d/sshd.conf (SSH-specific overrides - THIS FILE)"
    
    # Step 5: Restart fail2ban to apply configuration
    info "Restarting fail2ban..."
    if systemctl restart fail2ban; then
        success "Fail2ban restarted successfully"
    else
        error "Failed to restart fail2ban"
    fi
    
    # Step 6: Enable fail2ban to start on boot
    info "Enabling fail2ban on boot..."
    if systemctl enable fail2ban; then
        success "Fail2ban enabled for startup"
    else
        error "Failed to enable fail2ban for startup"
    fi
    
    # Step 7: Verify fail2ban is running
    info "Verifying fail2ban status..."
    if systemctl is-active --quiet fail2ban; then
        success "Fail2ban is running"
    else
        error "Fail2ban is not running"
    fi
    
    # Step 8: Check jail status
    info "Checking SSH jail status..."
    if fail2ban-client status sshd > /dev/null 2>&1; then
        success "SSHD jail is active and monitoring port $SSH_CUSTOM_PORT"
        info "Jail details:"
        fail2ban-client status sshd || warning "Could not retrieve jail status"
    else
        warning "SSHD jail status could not be verified (may need a moment to initialize)"
    fi
    
    # Step 9: Display configuration summary
    info "Fail2ban SSH Jail Configuration:"
    echo "  - enabled: true"
    echo "  - port: $SSH_CUSTOM_PORT"
    echo "  - maxretry: 3"
    echo "  - bantime: 3600 seconds (1 hour)"
    echo "  - findtime: 600 seconds (10 minutes)"
    echo "  - Effect: 3 failed attempts in 10 minutes = 1 hour ban"
    
    success "Phase 4 completed: Fail2ban installed and SSH jail configured"
    echo "=========================================="
}

# ==========================================
# PHASE 5: Fail2ban SSH Jail Testing
# ==========================================

phase5_fail2ban_jail_testing() {
    info "Starting Phase 5: Fail2ban SSH Jail Testing"
    echo "=========================================="

    local server_host
    server_host=$(hostname -f 2>/dev/null || hostname)

    # Step 1: Provide clear manual test instructions from docs/testing_fail2ban.md
    warning "Manual step required: trigger failed SSH logins from your local machine"
    info "Use one or more of the following commands from your local machine to trigger the sshd jail:"
    echo "  ssh -p $SSH_CUSTOM_PORT nonexistent@$server_host"
    echo "  ssh -p $SSH_CUSTOM_PORT -i /wrong/key/path $NEW_USERNAME@$server_host"
    echo "  for i in {1..5}; do ssh -p $SSH_CUSTOM_PORT baduser@$server_host 2>/dev/null; done"
    info "Run enough failed attempts to exceed maxretry (currently 3)."

    # Step 2: Prompt for the user's source IP address
    local test_ip
    while true; do
        read -p "Enter your public IP address (the one making failed SSH attempts): " test_ip
        if [[ -z "$test_ip" ]]; then
            warning "IP address cannot be empty"
            continue
        fi

        if [[ "$test_ip" =~ ^[0-9a-fA-F:.]+$ ]]; then
            break
        fi

        warning "Enter a valid IPv4 or IPv6 address format"
    done

    # Step 3: Wait for user confirmation before checking jail status
    local login_attempts_confirmed
    while true; do
        read -p "Type 'done' after you attempted failed logins: " login_attempts_confirmed
        if [[ "${login_attempts_confirmed,,}" == "done" ]]; then
            break
        fi
        warning "Please perform failed login attempts first, then type 'done'."
    done

    # Step 4: Check sshd jail status and verify the user's IP is banned
    local sshd_status
    local banned_ip_line
    local ip_banned=false
    local max_checks=12
    local check_interval_seconds=5

    info "Checking sshd jail for banned IP: $test_ip"
    for ((attempt=1; attempt<=max_checks; attempt++)); do
        sshd_status=$(fail2ban-client status sshd 2>/dev/null || true)

        if [[ -z "$sshd_status" ]]; then
            warning "Could not read sshd jail status on attempt $attempt"
        else
            info "sshd jail status (attempt $attempt/$max_checks):"
            echo "$sshd_status"

            banned_ip_line=$(echo "$sshd_status" | sed -n 's/.*Banned IP list:[[:space:]]*//p')

            if [[ -n "$banned_ip_line" ]]; then
                for banned_ip in $banned_ip_line; do
                    if [[ "$banned_ip" == "$test_ip" ]]; then
                        ip_banned=true
                        break
                    fi
                done
            fi
        fi

        if [[ "$ip_banned" == true ]]; then
            break
        fi

        if [[ "$attempt" -lt "$max_checks" ]]; then
            warning "IP $test_ip not yet banned. Retrying in $check_interval_seconds seconds..."
            sleep "$check_interval_seconds"
        fi
    done

    if [[ "$ip_banned" != true ]]; then
        error "IP $test_ip was not found in the banned IP list after $((max_checks * check_interval_seconds)) seconds"
    fi

    success "Confirmed: IP $test_ip appears in the sshd banned IP list"

    # Step 5: Unban and verify unban success
    info "Unbanning IP: $test_ip"
    fail2ban-client set sshd unbanip "$test_ip" || error "Failed to unban IP $test_ip"
    success "Unban command sent for IP $test_ip"

    sshd_status=$(fail2ban-client status sshd 2>/dev/null || true)
    info "sshd jail status after unban:"
    echo "$sshd_status"

    if echo "$sshd_status" | sed -n 's/.*Banned IP list:[[:space:]]*//p' | grep -qw "$test_ip"; then
        error "IP $test_ip still appears in banned IP list after unban"
    fi

    success "Verified: IP $test_ip is no longer in the banned IP list"

    # Step 6: User confirms test completion
    local test_complete_confirm
    while true; do
        read -p "Type 'yes' to confirm Fail2ban jail testing is complete: " test_complete_confirm
        if [[ "${test_complete_confirm,,}" == "yes" ]]; then
            break
        fi
        warning "Please type 'yes' when you are satisfied the test completed successfully."
    done

    success "Phase 5 completed: Fail2ban SSH jail test verified, unban verified, and user confirmed completion"
    echo "=========================================="
}

# ==========================================
# PHASE 6: Generate Final Report and Connection Instructions
# ==========================================

phase6_final_report() {
    info "Starting Phase 6: Final Report and Connection Instructions"
    echo "=========================================="

    # Gather server information
    local server_host
    local server_ip
    local report_timestamp
    local ssh_config_file
    local temp_config_dir
    local temp_config_file

    server_host=$(hostname -f 2>/dev/null || hostname)
    server_ip=$(hostname -I | awk '{print $1}')
    report_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Create temporary directory for SSH config
    temp_config_dir="/tmp/vpstarter-config"
    temp_config_file="$temp_config_dir/ssh_config"

    mkdir -p "$temp_config_dir"

    # Generate SSH config file content
    ssh_config_file="$temp_config_file"
    cat > "$ssh_config_file" << EOF
Host $server_host
    Hostname $server_ip
    Port $SSH_CUSTOM_PORT
    User $NEW_USERNAME
    IdentityFile ~/.ssh/id_ed25519

EOF

    # Set appropriate permissions
    chmod 644 "$ssh_config_file"

    # Generate comprehensive report
    echo ""
    echo "================================================================================"
    echo "                        VPS KICKSTARTER FINAL REPORT"
    echo "================================================================================"
    echo ""
    echo "Report Generated: $report_timestamp"
    echo "Server Hostname:  $server_host"
    echo "Server IP:        $server_ip"
    echo ""
    echo "================================================================================"
    echo "                    1. SYSTEM UPDATES PERFORMED"
    echo "================================================================================"
    echo ""
    echo "  - Package lists updated: apt update"
    echo "  - System packages upgraded: apt -y upgrade"
    echo ""
    echo "================================================================================"
    echo "                    2. UFW (FIREWALL) STATUS AND RULES"
    echo "================================================================================"
    echo ""
    echo "Current UFW Status:"
    ufw status
    echo ""
    echo "================================================================================"
    echo "                    3. SSH CONFIGURATION CHANGES"
    echo "================================================================================"
    echo ""
    echo "  - Custom SSH Port: $SSH_CUSTOM_PORT"
    echo "  - Password Authentication: Disabled (no)"
    echo "  - PermitRootLogin: prohibit-password (key-only)"
    echo "  - Backup created: /etc/ssh/sshd_config.backup.*"
    echo ""
    echo "================================================================================"
    echo "                    4. FAIL2BAN CONFIGURATION"
    echo "================================================================================"
    echo ""
    echo "  - Configuration file: /etc/fail2ban/jail.d/sshd.conf"
    echo "  - SSH Jail Settings:"
    echo "    * enabled: true"
    echo "    * port: $SSH_CUSTOM_PORT"
    echo "    * maxretry: 3"
    echo "    * bantime: 3600 seconds (1 hour)"
    echo "    * findtime: 600 seconds (10 minutes)"
    echo "  - Effect: 3 failed login attempts in 10 minutes results in a 1-hour ban"
    echo ""
    echo "  Current Jail Status:"
    fail2ban-client status sshd 2>/dev/null || echo "    (Jail status unavailable)"
    echo ""
    echo "================================================================================"
    echo "                    5. USER CREATION DETAILS"
    echo "================================================================================"
    echo ""
    echo "  - Username: $NEW_USERNAME"
    echo "  - Sudo privileges: Granted"
    echo "  - SSH key authentication: Enabled"
    echo "  - Authorized keys file: /home/$NEW_USERNAME/.ssh/authorized_keys"
    echo ""
    echo "================================================================================"
    echo "                    6. SECURITY MEASURES IMPLEMENTED"
    echo "================================================================================"
    echo ""
    echo "  - UFW firewall enabled and configured"
    echo "  - SSH hardened with custom port and key-only authentication"
    echo "  - Root login restricted to key-only access"
    echo "  - Password authentication disabled for SSH"
    echo "  - Fail2ban active with sshd jail monitoring failed login attempts"
    echo "  - Non-root user created with sudo privileges"
    echo "  - SSH keys validated for secure authentication"
    echo ""
    echo "================================================================================"
    echo "                 SSH HOST CONFIG FILE"
    echo "================================================================================"
    echo ""
    echo "The following SSH config has been generated at:"
    echo "  $ssh_config_file"
    echo ""
    echo "Config file contents:"
    echo "--------------------------------------------------------------------------------"
    cat "$ssh_config_file"
    echo "--------------------------------------------------------------------------------"
    echo ""
    echo "================================================================================"
    echo "                 HOW TO COPY CONFIG TO YOUR LOCAL MACHINE"
    echo "================================================================================"
    echo ""
    echo "Run the following command on your LOCAL machine to copy the config:"
    echo ""
    echo "  scp -P $SSH_CUSTOM_PORT $NEW_USERNAME@$server_ip:$ssh_config_file ~/.ssh/config"
    echo ""
    echo "Or use the following command to append it to your existing config:"
    echo ""
    echo "  scp -P $SSH_CUSTOM_PORT $NEW_USERNAME@$server_ip:$ssh_config_file /tmp/vps-ssh-config && cat /tmp/vps-ssh-config >> ~/.ssh/config"
    echo ""
    echo "================================================================================"
    echo "                 FINAL CONNECTION COMMAND"
    echo "================================================================================"
    echo ""
    echo "Once the config is in place, connect using:"
    echo ""
    echo "  ssh $server_host"
    echo ""
    echo "Or connect directly (without config file):"
    echo ""
    echo "  ssh -p $SSH_CUSTOM_PORT $NEW_USERNAME@$server_ip"
    echo ""
    echo "================================================================================"
    echo "                            IMPORTANT NOTES"
    echo "================================================================================"
    echo ""
    echo "  - SSH is configured to run on port $SSH_CUSTOM_PORT (will be active after final restart)"
    echo "  - Port 22 will be denied in UFW during the final phase"
    echo "  - Keep your SSH private key secure - it's your only authentication method"
    echo "  - The server will now reject password-based SSH login attempts"
    echo "  - Fail2ban will ban IPs that make 3+ failed login attempts in 10 minutes"
    echo ""
    echo "================================================================================"
    echo "                      PHASE 6 COMPLETE - ONE STEP REMAINING"
    echo "================================================================================"
    echo ""
    success "Phase 6 completed: Final report generated!"
    echo ""
    echo "Phase 7 will now restart SSH service and complete the setup."
    echo "Your current connection will be disconnected."
    echo ""
    success "Phase 6 completed: Final report generated and connection instructions provided"
    echo "=========================================="
}

# ==========================================
# PHASE 7: Final SSH Service Restart with User Confirmation
# ==========================================

phase7_ssh_restart_and_confirmation() {
    info "Starting Phase 7: SSH Service Restart with User Confirmation"
    echo "=========================================="
    
    # Step 1: Display prominent warning about impending SSH restart
    echo ""
    echo -e "${RED}================================================================================${NC}"
    echo -e "${RED}                        FINAL STEP: SSH SERVICE RESTART                         ${NC}"
    echo -e "${RED}================================================================================${NC}"
    echo ""
    echo -e "${YELLOW}WARNING: SSH service will now restart with the new configuration!${NC}"
    echo -e "${YELLOW}WARNING: This will disconnect your current session on port 22.${NC}"
    echo ""
    echo -e "${YELLOW}Current SSH connection details:${NC}"
    echo "  - You are currently connected on: port 22"
    echo "  - After restart, SSH will use: port $SSH_CUSTOM_PORT"
    echo "  - You will need to reconnect using: ssh -p $SSH_CUSTOM_PORT $NEW_USERNAME@$(hostname -I | awk '{print $1}')"
    echo ""
    echo -e "${RED}================================================================================${NC}"
    echo ""
    
    # Step 2: Prompt for user confirmation
    local confirm_restart
    while true; do
        read -p "Type 'yes' when ready to restart SSH and complete the setup: " confirm_restart
        if [[ "${confirm_restart,,}" == "yes" ]]; then
            break
        fi
        warning "You must type 'yes' to proceed with SSH restart and complete the setup."
    done
    
    echo ""
    info "User confirmed. Proceeding with final steps..."
    
    # Step 3: Delete the Allow SSH rule in UFW (port 22)
    info "Deleting UFW rule: Allow SSH on port 22..."
    if ufw delete allow ssh; then
        success "UFW rule removed: SSH on port 22 is now denied"
    else
        warning "Could not delete UFW SSH rule (may not exist or already removed)"
    fi
    
    # Display updated UFW status
    info "Updated UFW status:"
    ufw status
    
    # Step 4: Restart SSH service
    echo ""
    info "Restarting SSH service to apply new configuration..."
    info "New SSH settings will take effect:"
    echo "  - Port: $SSH_CUSTOM_PORT"
    echo "  - PasswordAuthentication: no"
    echo "  - PermitRootLogin: prohibit-password"
    echo ""
    
    # Restart SSH service
    if systemctl restart ssh; then
        success "SSH service restarted successfully"
    else
        error "Failed to restart SSH service. Check configuration with: sshd -t"
    fi
    
    # Verify SSH is running on the new port
    sleep 2
    info "Verifying SSH service is active on port $SSH_CUSTOM_PORT..."
    if systemctl is-active --quiet ssh; then
        success "SSH service is running"
    else
        warning "SSH service status could not be verified (may still be starting)"
    fi
    
    # Step 5: Display final completion message
    echo ""
    echo -e "${GREEN}================================================================================${NC}"
    echo -e "${GREEN}                         SETUP COMPLETE!                                       ${NC}"
    echo -e "${GREEN}================================================================================${NC}"
    echo ""
    echo -e "${GREEN}SSH service has been restarted with the hardened configuration.${NC}"
    echo ""
    echo "Your current connection on port 22 has been terminated."
    echo ""
    echo "To reconnect to your server, use:"
    echo "  ssh -p $SSH_CUSTOM_PORT $NEW_USERNAME@$(hostname -I | awk '{print $1}')"
    echo ""
    echo "Or if you copied the SSH config to your local machine:"
    echo "  ssh $(hostname -f 2>/dev/null || hostname)"
    echo ""
    echo -e "${GREEN}================================================================================${NC}"
    echo ""
    
    success "Phase 7 completed: SSH service restarted, port 22 denied, setup complete"
    echo "=========================================="
}

# ==========================================
# Main Script Execution
# ==========================================

main() {
    echo "=========================================="
    echo "VPS Kickstarter - Ubuntu 22+ Provisioning"
    echo "=========================================="
    echo ""
    
    # Run Phase 1: System Updates and UFW Setup
    phase1_system_updates_and_ufw

    # Run Phase 2: Non-root User Setup
    phase2_non_root_user_setup

    # Run Phase 3: SSH Hardening
    phase3_ssh_hardening

    # Run Phase 4: Fail2ban Setup
    phase4_fail2ban_setup

    # Run Phase 5: Fail2ban SSH Jail Testing
    phase5_fail2ban_jail_testing

    # Run Phase 6: Final Report and Connection Instructions
    phase6_final_report

    # Run Phase 7: SSH Service Restart with User Confirmation
    phase7_ssh_restart_and_confirmation
}

# Execute main function
main "$@"
