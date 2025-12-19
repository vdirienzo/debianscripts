# Creating Custom Notifiers for Autoclean

This guide explains how to create your own notification plugins for Autoclean.

## File Structure

Create a file with `.notifier` extension in the `plugins/notifiers/` directory:

```
plugins/notifiers/
├── TUTORIAL.md          # This file
├── desktop.notifier     # Desktop notifications (notify-send)
├── telegram.notifier    # Telegram bot
├── email.notifier       # Email notifications
└── yournotifier.notifier  # Your custom notifier
```

## Notifier Template

```bash
# ============================================================================
# Autoclean Notifier Plugin: Your Notifier Name
# ============================================================================
# Brief description of what this notifier does
# ============================================================================

# === METADATA (Required) ===
NOTIFIER_NAME="Your Notifier Name"
NOTIFIER_CODE="yourcode"
NOTIFIER_DESCRIPTION="Brief description for the menu"
NOTIFIER_DEPS="curl jq"  # Space-separated dependencies

# === CONFIGURATION SCHEMA ===
# Define which variables need to be configured by the user
# Format: ["VARIABLE_NAME"]="Description shown in config menu"
declare -A NOTIFIER_FIELDS=(
    ["NOTIFIER_YOURCODE_API_KEY"]="Your API key"
    ["NOTIFIER_YOURCODE_ENDPOINT"]="API endpoint URL"
)

# === REQUIRED FUNCTIONS ===

# Check if system dependencies are available
# Return 0 if OK, 1 if missing
notifier_check_deps() {
    command -v curl &>/dev/null
}

# Check if notifier is properly configured
# Return 0 if configured, 1 if not
notifier_is_configured() {
    [[ -n "$NOTIFIER_YOURCODE_API_KEY" && -n "$NOTIFIER_YOURCODE_ENDPOINT" ]]
}

# Send a notification
# Args: $1=title, $2=message, $3=severity (critical/error/warning/success/info)
# Return 0 on success, 1 on failure
notifier_send() {
    local title="$1"
    local message="$2"
    local severity="${3:-info}"

    # Your notification logic here
    curl -s -X POST "$NOTIFIER_YOURCODE_ENDPOINT" \
         -H "Authorization: Bearer $NOTIFIER_YOURCODE_API_KEY" \
         -d "title=$title" \
         -d "message=$message" \
         -d "priority=$severity" \
         --connect-timeout 10 \
         --max-time 30 \
         2>/dev/null

    return $?
}

# Send a test notification
# Called when user presses [T] in the menu
notifier_test() {
    notifier_send "Autoclean Test" "Test notification from $(hostname)" "info"
}

# Display setup help
# Called when user presses [H] in the menu
notifier_help() {
    cat << 'HELP_EOF'
================================================================================
                    YOUR NOTIFIER - SETUP GUIDE
================================================================================

STEP 1: Get an API Key
----------------------
1. Go to https://example.com
2. Create an account
3. Generate an API key

STEP 2: Configure in Autoclean
------------------------------
Enter the values in the configuration menu:
  - API Key: Your key from step 1
  - Endpoint: https://api.example.com/notify

STEP 3: Test
------------
Use the [T] option to send a test notification.

TROUBLESHOOTING:
----------------
- Check your API key is valid
- Verify network connectivity
- Check firewall allows outbound HTTPS

================================================================================
HELP_EOF
}
```

## Required Functions

| Function | Purpose | Return Value |
|----------|---------|--------------|
| `notifier_check_deps()` | Verify system dependencies | 0=OK, 1=missing |
| `notifier_is_configured()` | Check if user has configured it | 0=configured, 1=not |
| `notifier_send()` | Send the notification | 0=success, 1=failure |
| `notifier_test()` | Send a test message | 0=success, 1=failure |
| `notifier_help()` | Display setup instructions | N/A (just prints) |

## Severity Levels

The `$severity` parameter in `notifier_send()` can be:

| Level | Usage |
|-------|-------|
| `critical` | Disk failure, system crash |
| `error` | Operation failed |
| `warning` | Reboot needed, attention required |
| `success` | Operation completed successfully |
| `info` | General information |

## Configuration Variables

- Use the `NOTIFIER_` prefix for all config variables
- Include your notifier code in the variable name: `NOTIFIER_YOURCODE_*`
- These will be saved to `autoclean.conf` when user saves configuration

## Security Notes

1. The notifier file is validated before loading (no command substitution allowed)
2. API keys are partially masked in the config menu
3. Notifications never block the main script (failures are logged but ignored)

## Testing Your Notifier

1. Create your `.notifier` file in `plugins/notifiers/`
2. Run `sudo ./autoclean.sh`
3. Press `[O]` to open notifications menu
4. Your notifier should appear in the list
5. Press `[C]` to configure, `[T]` to test

## Example Notifiers

See the existing notifiers for reference:

- `desktop.notifier` - Simplest example, no config needed
- `telegram.notifier` - API-based with config fields
- `email.notifier` - Multiple backends (mail/msmtp/sendmail)

## Adding More Notifiers

Common services that could be implemented:

- **Slack**: Webhook URL based
- **Discord**: Webhook URL based
- **ntfy.sh**: Simple HTTP POST
- **Pushover**: API key + user key
- **Gotify**: Server URL + token
- **Matrix**: Homeserver + token
- **IFTTT**: Webhook key + event name
