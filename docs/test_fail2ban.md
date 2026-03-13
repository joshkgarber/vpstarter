# Testing Fail2ban SSH Jail

How to test your jail:

## Attempt SSH Login with Wrong Credentials
Since you've disabled password auth, you can still trigger failures by:
- Attempting to log in with a non-existent username
- Using an invalid key file (or omitting `-i` flag if keys are required)
- Connecting to the custom port with wrong credentials

```bash
# These will generate failed login attempts
ssh -p YOUR_PORT nonexistent@your_server
ssh -p YOUR_PORT -i /wrong/key/path user@your_server
```

## Simulate Rapid Failed Attempts
Script multiple failures to trigger the jail (respects your `maxretry` setting):

```bash
for i in {1..5}; do ssh -p YOUR_PORT baduser@your_server 2>/dev/null; done
```
