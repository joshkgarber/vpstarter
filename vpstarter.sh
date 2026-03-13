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
# PHASE 2: SSH Hardening
# ==========================================

# Global variable to store SSH port for later phases
SSH_CUSTOM_PORT=""

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

phase2_ssh_hardening() {
    info "Starting Phase 2: SSH Hardening"
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
    
    success "Phase 2 completed: SSH configuration prepared for port $SSH_CUSTOM_PORT"
    success "SSH restart deferred to final confirmation phase"
    info "Port $SSH_CUSTOM_PORT stored in SSH_CUSTOM_PORT for later phases"
    echo "=========================================="
}

# ==========================================
# PHASE 3: Fail2ban Setup
# ==========================================

phase3_fail2ban_setup() {
    info "Starting Phase 3: Fail2ban Setup"
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
    
    success "Phase 3 completed: Fail2ban installed and SSH jail configured"
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
    
    # Run Phase 2: SSH Hardening
    phase2_ssh_hardening
    
    # Run Phase 3: Fail2ban Setup
    phase3_fail2ban_setup
    
    # Future phases will be implemented here
    info "Phases 1, 2, and 3 complete. Additional phases will be implemented in subsequent updates."
}

# Execute main function
main "$@"
