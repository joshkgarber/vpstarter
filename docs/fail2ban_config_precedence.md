# Fail2ban Configuration Precedence

Fail2ban loads configuration files in this order:

1. `/etc/fail2ban/jail.conf` (default settings)
2. `/etc/fail2ban/jail.local` (overrides)
3. `/etc/fail2ban/jail.d/*.conf` (additional overrides, alphabetically)

## How They Interact

- **jail.local** settings take precedence over jail.conf
- **jail.d/sshd.conf** settings take precedence over both

If the same option appears in multiple files, the **last one loaded wins**.

## Best Practice

Create `jail.d/sshd.conf` for SSH-only overrides.
