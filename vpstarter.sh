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
    
    # Step 4: Enable UFW
    # UFW will be enabled without any rules initially
    # SSH rules will be configured in Phase 2 after SSH hardening
    info "Enabling UFW firewall..."
    
    if ufw enable; then
        success "UFW enabled successfully"
    else
        error "Failed to enable UFW"
    fi
    
    # Step 5: Test UFW status and verify it's active
    # This confirms the firewall is running and will protect the server
    info "Verifying UFW status..."
    
    UFW_STATUS=$(ufw status | grep -i "status:" | awk '{print $2}')
    
    if [[ "$UFW_STATUS" == "active" ]]; then
        success "UFW is active and protecting the server"
    else
        error "UFW is not active. Expected status: active, Got: $UFW_STATUS"
    fi
    
    # Display current UFW status for user information
    info "Current UFW status:"
    ufw status
    
    success "Phase 1 completed: System updated and UFW installed and enabled"
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
        info "Attempting to enable SSH service..."
        if systemctl enable ssh; then
            success "SSH service enabled successfully"
        else
            error "Failed to enable SSH service"
        fi
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
    
    warning "IMPORTANT: Changing the SSH port will disconnect active SSH sessions."
    warning "Ensure you have an alternative method to access the server if needed."
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
        
        if [[ "$user_port" -lt 1 || "$user_port" -gt 65535 ]]; then
            error "Port must be between 1 and 65535"
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
    
    # Step 6: Validate SSH configuration before restarting
    info "Validating SSH configuration..."
    if sshd -t; then
        success "SSH configuration is valid"
    else
        error "SSH configuration is invalid. Check $ssh_config"
    fi
    
    # Step 7: Restart SSH service
    info "Restarting SSH service to apply changes..."
    if systemctl restart ssh; then
        success "SSH service restarted successfully"
    else
        error "Failed to restart SSH service"
    fi
    
    # Step 8: Verify SSH is listening on new port
    info "Verifying SSH is listening on port $SSH_CUSTOM_PORT..."
    sleep 2  # Give service time to bind
    
    if ss -tlnp | grep -q ":$SSH_CUSTOM_PORT"; then
        success "SSH is now listening on port $SSH_CUSTOM_PORT"
    else
        warning "Could not verify SSH is listening on port $SSH_CUSTOM_PORT"
        warning "Please manually verify with: ss -tlnp | grep ssh"
    fi
    
    # Step 9: Configure UFW for custom SSH port
    info "Configuring UFW firewall rules..."
    
    # Allow the custom SSH port
    if ufw allow "$SSH_CUSTOM_PORT/tcp"; then
        success "UFW rule added: allow port $SSH_CUSTOM_PORT/tcp"
    else
        error "Failed to add UFW rule for port $SSH_CUSTOM_PORT"
    fi
    
    # Deny default SSH port (22)
    if ufw deny ssh; then
        success "UFW rule added: deny SSH on port 22"
    else
        warning "Failed to add UFW deny rule for port 22"
    fi
    
    # Step 10: Verify UFW status
    info "Verifying UFW status..."
    ufw status verbose
    
    success "Phase 2 completed: SSH hardened and running on port $SSH_CUSTOM_PORT"
    info "SSH port $SSH_CUSTOM_PORT has been stored for Fail2ban configuration"
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
    
    # Future phases will be implemented here
    info "Phases 1 and 2 complete. Additional phases will be implemented in subsequent updates."
}

# Execute main function
main "$@"
