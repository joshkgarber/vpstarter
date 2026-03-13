# VPStarter - VPS Security Hardening Script

VPStarter is a comprehensive bash script designed to provision and secure a fresh Ubuntu VPS with essential security measures. It automates the initial server setup process while guiding you through important manual steps.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [What the Script Does](#what-the-script-does)
- [Interactive Prompts](#interactive-prompts)
- [Manual Steps You Must Perform](#manual-steps-you-must-perform)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

## Overview

VPStarter secures your VPS in 7 phases:
1. **System Updates** - Updates packages and configures UFW firewall
2. **User Setup** - Creates a non-root user with sudo access
3. **SSH Hardening** - Moves SSH to a non-standard port and disables password auth
4. **Fail2ban** - Installs and configures intrusion prevention
5. **Testing** - Validates fail2ban is working correctly
6. **Report** - Generates connection details and SSH config
7. **Finalization** - Applies changes and restarts SSH

## Prerequisites

- **Operating System**: Ubuntu 22.04 LTS or newer
- **Access**: Root access (run as root or with sudo)
- **Network**: Internet connection for package installation
- **Local Machine**: SSH key pair already generated (`~/.ssh/id_rsa.pub` or `~/.ssh/id_ed25519.pub`)

### Pre-flight Checklist

Before running VPStarter, ensure you have:
- [ ] Root access to a fresh Ubuntu VPS
- [ ] SSH key pair on your local machine
- [ ] SSH client installed locally
- [ ] 10-15 minutes of uninterrupted time

## Installation

### Option 1: Quick Start (Recommended)

Download and run the script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/joshkgarber/vpstarter/main/vpstarter.sh | sudo bash
```

**Note**: The script is interactive and will pause for your input at several points. Don't run this in an automated environment.

### Option 2: Manual Download

1. Download the script:
   ```bash
   wget https://raw.githubusercontent.com/joshkgarber/vpstarter/main/vpstarter.sh
   ```

2. Make it executable:
   ```bash
   chmod +x vpstarter.sh
   ```

3. Run as root:
   ```bash
   sudo ./vpstarter.sh
   ```

## What the Script Does

### Security Measures Implemented

| Measure | What It Does | Why It Helps |
|---------|--------------|--------------|
| **UFW Firewall** | Blocks all incoming traffic except SSH | Prevents unauthorized access to services |
| **SSH Port Change** | Moves SSH from default port 22 to a random port (10,000-65,535) | Reduces automated attack attempts |
| **Password Auth Disabled** | Requires SSH keys for authentication | Prevents brute-force password attacks |
| **Root Login Restricted** | Root can only login with keys, not passwords | Protects the most privileged account |
| **Fail2ban** | Bans IPs after 3 failed login attempts | Stops brute-force attacks in progress |
| **Non-root User** | Creates a regular user with sudo access | Follows principle of least privilege |

### System Changes

The script will modify:
- `/etc/ssh/sshd_config` - SSH server configuration
- `/etc/fail2ban/jail.d/sshd.conf` - Fail2ban SSH jail rules
- `/etc/ufw/before.rules` - Firewall rules (temporary)
- Creates new user account with sudo privileges
- Updates all system packages

**Important**: The original SSH port (22) remains open until the very end to prevent lockouts.

## Interactive Prompts

The script will pause and ask for your input at these points:

### 1. Username and Password
```
Enter username for new admin account: [your_input]
Enter password: [hidden_input]
```

### 2. SSH Port Selection
```
Suggested SSH port: [random_port_number]
Accept this port? (y/n/custom): [y/n or enter custom port]
```

### 3. SSH Key Transfer
```
[MANUAL STEP REQUIRED]
Run this command from your local machine:
ssh-copy-id -p [port] username@[server_ip]

Press Enter when ready to validate the SSH key...
```

### 4. Fail2ban Testing
```
Enter your local IP address: [your_ip]
Open another terminal and run 3 failed SSH attempts.
Press Enter when ready to check ban status...
```

### 5. Final Confirmation
```
⚠️  WARNING: SSH service will restart and disconnect you!
You will need to reconnect on port [new_port]
Type 'yes' to continue: [type yes]
```

## Manual Steps You Must Perform

### 1. Copy Your SSH Key

After the script creates your user, you'll need to copy your SSH public key:

```bash
# From your LOCAL machine (not the server)
ssh-copy-id -p [PORT] [USERNAME]@[SERVER_IP]
```

Example:
```bash
ssh-copy-id -p 42424 admin@192.168.1.100
```

### 2. Test Fail2ban Jail

The script will guide you through testing:
1. Open a second terminal on your local machine
2. Try to SSH with wrong passwords 3 times:
   ```bash
   ssh -p [PORT] wronguser@[SERVER_IP]
   # Enter wrong passwords
   ```
3. Return to the script and confirm
4. The script will verify your IP was banned and unban it

### 3. Save SSH Config

At the end, the script generates an SSH config at:
```
/tmp/vpstarter-config/ssh_config
```

Copy it to your local machine:
```bash
# From your LOCAL machine
scp [USERNAME]@[SERVER_IP]:/tmp/vpstarter-config/ssh_config ~/.ssh/config.d/vpstarter
```

### 4. Reconnect After Script Completes

After the SSH restart:
```bash
ssh -p [NEW_PORT] [USERNAME]@[SERVER_IP]
```

## Troubleshooting

### "Permission denied" when copying SSH key

**Cause**: Wrong port or username

**Solution**:
- Double-check the port number shown in the script output
- Verify the username matches what you entered
- Make sure you're running the command from your local machine

### Locked out after script completes

**Cause**: SSH key not properly copied or wrong port

**Recovery Options**:
1. **VNC/Console**: Use your provider's web console (most VPS providers offer this)
2. **Recovery Mode**: Boot into recovery mode via provider's control panel
3. **Contact Support**: Ask provider to restore SSH on port 22 temporarily

**Prevention**:
- Always keep the terminal window open during the script
- Don't close the script until you've successfully reconnected on the new port

### Fail2ban test shows "IP not banned"

**Cause**: Not enough failed attempts or wrong IP

**Solution**:
- Ensure you made exactly 3 failed attempts from the correct IP
- Check your public IP with `curl ifconfig.me`
- Retry the test sequence

### "Port already in use" error

**Cause**: The randomly selected port is being used by another service

**Solution**:
- Enter a custom port when prompted (choose between 10000-65535)
- Avoid ports 3306 (MySQL), 5432 (PostgreSQL), 8080 (common web)

### Script interrupted or connection lost

**Solution**:
1. Reconnect and run the script again
2. The script is idempotent for most steps
3. If SSH was already changed, use the new port to reconnect

## Security Considerations

### ⚠️ Important Warnings

1. **Always use SSH keys**: Never enable password authentication for SSH
2. **Keep your keys safe**: Store private keys securely and never share them
3. **Regular updates**: Run `apt update && apt upgrade` regularly
4. **Monitor logs**: Check `/var/log/auth.log` for suspicious activity
5. **Backup keys**: Keep a backup of your SSH keys in a secure location

### What VPStarter Doesn't Do

VPStarter provides basic security hardening, but you should also:
- Set up automatic security updates (`unattended-upgrades`)
- Configure log monitoring
- Set up a firewall for specific applications
- Consider using key-based authentication for additional services
- Regularly review user accounts and permissions

### Security Best Practices After Running VPStarter

1. **Enable automatic updates**:
   ```bash
   sudo apt install unattended-upgrades
   sudo dpkg-reconfigure -plow unattended-upgrades
   ```

2. **Set up logwatch** for security reports:
   ```bash
   sudo apt install logwatch
   ```

3. **Consider 2FA for SSH** (advanced):
   Install `libpam-google-authenticator` for additional security

4. **Disable root login completely** (optional, advanced):
   Edit `/etc/ssh/sshd_config` and set `PermitRootLogin no`

---

## Support

For issues, questions, or contributions, please visit:
https://github.com/joshkgarber/vpstarter

## License

MIT License - See LICENSE file for details

---

**Remember**: Security is a process, not a destination. Stay informed about security updates and best practices!
