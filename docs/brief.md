# Brief

Create a kickstarter script for Ubuntu 22+ VPS provisioning which will be run as root.

The script is not run automatically on startup, rather it is run by a human after downloading it from github.

## Components

- UFW config
- Non-root user creation
- SSH config
- Fail2ban installation and config

## Requirements

**Non-functional requirements**

- Use comments in the script to describe what is being done.

**Functional requirements**

- Run Upgrades
    - `apt update && apt -y upgrade`
- UFW
    - Install UFW
    - Allow ssh connections
    - Enable ufw
    - Test
- New User
    - create the user (take name as input)
    - give the user sudo privileges
    - instruct to add ssh key to host using ssh-copy-id on the remote system
    - check that ssh key was added successfully
- SSH
    - check status
    - enable if needed
    - configure and harden
        - take custom port number as input (provide a pseudo-random suggestion)
    - output ready-made host file contents
- Fail2ban
    - install
    - create config file
    - configure sshd jail using `sed`
    - start and enable
    - test sshd jail (provide instructions to user and request confirmation that instructions were carried out, then check the jail.)
- Output a report documenting what was achieved.

---

## Implementation Notes

# Install UFW

- Check UFW is installed: `which ufw`
- Install UFW: `apt install -y ufw`
- Check UFW status: `ufw status`

## Enable UFW

- Allow SSH connections: `ufw allow ssh`
- Enable UFW: `ufw enable`

### Enable SSH

SSH is usually installed and active by default, but might not be enabled. Enable the ssh service if not already.

- View status: `systemctl status ssh`
- Enable if needed: `systemctl enable ssh`

### Add a non-root user

- Create a new user: `adduser <user>`

The command above does the following:

- Creates the user
- Creates a group with the same name as the user and adds the user to that group
- Creates a home directory for the user with skeleton files like `.bashrc`
- Adds the user to the `users` group

### Give the non-root user sudo privileges

- Give the user sudo privileges: `adduser <user> sudo`

### Add a remote SSH key

- Create an ssh key: `ssh-keygen -C "your_email@example.com"`
- Add an SSH key to the host: `ssh-copy-id -i identity_file user@hostname` (run on the remote system)
- Check it was added correctly: read the `./ssh_key_validator.md` file for detailed implementation example.

### Configure and harden SSH

Upgrade the security of ssh connections: 

- Set the port number to something other than 22 to evade unwanted connections: read the `./ssh_random_port_generator.md` file for a detailed impelementation example.
- Disable password authentication to force ssh keys.
    - Change PasswordAuthentication yes to no
    - Change PermitRootLogin to prohibit-password
- Configure the firewall to allow inbound TCP connections via the new port: `ufw allow XXXXX/tcp`
- Run `systemctl restart ssh`
- Run `systemctl status ssh` and check that the port number has been changed.
- Disallow ssh on port 22: `ufw deny ssh`
- Check to confirm: `ufw status`

### Example host config file contents

(To be put on the local machine in ~/.ssh/config)

```
Host host_name
  Hostname server_public_ip
  Port XXXX
  User user_name
  IdentityFile path_to_public_key
```

### Install Fail2Ban

Fail2Ban will protect the server from hackers trying to access the server via SSH.

Install via apt:

```
apt update
apt install fail2ban
```

Create a config file: `sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local`

In that file, configure the `ssh` jail:

```
[sshd]
enabled = true
port = XXXXX
maxretry = 3
bantime = 3600
findtime = 600
```

The config above means three failed attempts in 10 minutes → banned for an hour.

```
systemctl restart fail2ban
systemctl enable fail2ban
```

### Inspect Fail2Ban jails

- `fail2ban-client status`
- `fail2ban-client status <jail>` e.g. `fail2ban-client status sshd`

### Test Fail2Ban

Follow these steps to test the `sshd` jail.

1. Trigger the jail by failing login several times
2. Check the jail with `fail2ban-client status sshd`
3. You should see the IP in the list of banned IPs.

To unban the IP address: `fail2ban-client set sshd unbanip 111.111.111.111`
