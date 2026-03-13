# SSH Random Port Generator

Here's a simple bash script that generates a pseudo-random non-standard SSH port:

```bash
#!/bin/bash

# Generate a pseudo-random SSH port (non-standard, outside common ranges)
# Standard SSH port is 22
# Avoid well-known ports (0-1023) and common service ports

generate_ssh_port() {
    # Generate random number between 10000-65535
    local port=$((RANDOM % 55536 + 10000))
    
    # List of ports to avoid (common services)
    local avoid_ports=(
        3306 3389 5432 5900 8080 8443 9200 27017 6379
    )
    
    # Check if port is in avoid list
    for avoid in "${avoid_ports[@]}"; do
        if [ "$port" -eq "$avoid" ]; then
            generate_ssh_port  # Recursively try again
            return
        fi
    done
    
    echo "$port"
}

# Main execution
PORT=$(generate_ssh_port)
echo "Generated SSH Port: $PORT"
```
