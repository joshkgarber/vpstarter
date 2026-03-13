# SSH Authorized Keys Validator

Here's a bash script that validates each key in `~/.ssh/authorized_keys`:

```bash
#!/bin/bash

AUTHORIZED_KEYS_FILE="$HOME/.ssh/authorized_keys"
VALID_COUNT=0
INVALID_COUNT=0

# Check if file exists
if [[ ! -f "$AUTHORIZED_KEYS_FILE" ]]; then
    echo "Error: $AUTHORIZED_KEYS_FILE not found"
    exit 1
fi

# Read the file line by line
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Validate the key using ssh-keygen
    if echo "$line" | ssh-keygen -i -f - &>/dev/null; then
        ((VALID_COUNT++))
        echo "✓ Valid key #$VALID_COUNT"
    else
        ((INVALID_COUNT++))
        echo "✗ Invalid key: ${line:0:50}..."
    fi
done < "$AUTHORIZED_KEYS_FILE"

# Summary
echo ""
echo "========================================"
echo "Validation Summary:"
echo "Valid keys:   $VALID_COUNT"
echo "Invalid keys: $INVALID_COUNT"
echo "========================================"

# Exit with error if any invalid keys found
[[ $INVALID_COUNT -eq 0 ]] && exit 0 || exit 1
```

## Features

- ✓ Validates each key in `~/.ssh/authorized_keys`
- ✓ Skips empty lines and comment lines
- ✓ Uses `ssh-keygen -i -f -` to validate keys
- ✓ Provides a summary of valid/invalid keys
- ✓ Returns exit code 0 if all keys are valid, 1 if any are invalid
- ✓ Suppresses ssh-keygen output for cleaner display

## Notes

- The script reads each line as a potential key
- Invalid keys are shown truncated (first 50 characters) to keep output readable
- To validate a different authorized_keys file, modify the `AUTHORIZED_KEYS_FILE` variable
