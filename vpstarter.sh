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
# Main Script Execution
# ==========================================

main() {
    echo "=========================================="
    echo "VPS Kickstarter - Ubuntu 22+ Provisioning"
    echo "=========================================="
    echo ""
    
    # Run Phase 1: System Updates and UFW Setup
    phase1_system_updates_and_ufw
    
    # Future phases will be implemented here
    info "Phase 1 complete. Additional phases will be implemented in subsequent updates."
}

# Execute main function
main "$@"
