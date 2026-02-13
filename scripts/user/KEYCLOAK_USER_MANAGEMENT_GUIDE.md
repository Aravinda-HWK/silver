# Keycloak User Management Guide

This guide shows you how to use the `keycloak_manage_users.sh` script to manage email users in Silver Mail with Keycloak.

## Prerequisites

1. **Keycloak must be running**
   ```bash
   # Check if Keycloak is running
   docker ps | grep keycloak
   
   # If not running, start it
   cd /path/to/silver/scripts/service
   ./start-silver-keycloak.sh
   ```

2. **The silver-mail realm must exist**
   - This is automatically created when you run `start-silver-keycloak.sh`
   - You can verify by accessing: `http://your-domain:8080/admin`

## Quick Start

Navigate to the user management directory:
```bash
cd scripts/user
```

## Commands Overview

### 1. Add a New User

**With password:**
```bash
./keycloak_manage_users.sh add-user <username> <email> <password>
```

**Example:**
```bash
./keycloak_manage_users.sh add-user john john@aravindahwk.org SecurePass123
```

**Without password (can be set later):**
```bash
./keycloak_manage_users.sh add-user john john@aravindahwk.org
```

**Output:**
```
Authenticating with Keycloak...
  - Requesting access token from Keycloak...
  ✓ Authentication successful
Creating user 'john' with email 'john@aravindahwk.org'...
✓ User 'john' created successfully
✓ Password set successfully

User Details:
  Username: john
  Email:    john@aravindahwk.org
  Status:   Enabled
```

### 2. List All Users

```bash
./keycloak_manage_users.sh list-users
```

**Output:**
```
Authenticating with Keycloak...
  - Requesting access token from Keycloak...
  ✓ Authentication successful
Users in realm 'silver-mail':

  • john <john@aravindahwk.org> - ✓ Enabled
  • jane <jane@aravindahwk.org> - ✓ Enabled
  • admin <admin@aravindahwk.org> - ✓ Enabled
```

### 3. Reset User Password

```bash
./keycloak_manage_users.sh reset-password <username> <new-password>
```

**Example:**
```bash
./keycloak_manage_users.sh reset-password john NewSecurePass456
```

**Output:**
```
Authenticating with Keycloak...
  - Requesting access token from Keycloak...
  ✓ Authentication successful
✓ Password reset successfully for user 'john'
```

### 4. Delete a User

```bash
./keycloak_manage_users.sh delete-user <username>
```

**Example:**
```bash
./keycloak_manage_users.sh delete-user john
```

**Output:**
```
Authenticating with Keycloak...
  - Requesting access token from Keycloak...
  ✓ Authentication successful
✓ User 'john' deleted successfully
```

### 5. Get User Details

```bash
./keycloak_manage_users.sh get-user <username>
```

**Example:**
```bash
./keycloak_manage_users.sh get-user john
```

**Output:**
```
Authenticating with Keycloak...
  - Requesting access token from Keycloak...
  ✓ Authentication successful
User Details:
[
  {
    "id": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
    "username": "john",
    "email": "john@aravindahwk.org",
    "emailVerified": true,
    "enabled": true,
    "firstName": "",
    "lastName": "",
    "createdTimestamp": 1739421234567
  }
]
```

## Step-by-Step Example: Creating Multiple Users

Here's a complete example of setting up users for your mail system:

```bash
# Navigate to the user management directory
cd /path/to/silver/scripts/user

# Make sure the script is executable
chmod +x keycloak_manage_users.sh

# Add first user
./keycloak_manage_users.sh add-user alice alice@aravindahwk.org Alice123!

# Add second user
./keycloak_manage_users.sh add-user bob bob@aravindahwk.org Bob456!

# Add third user
./keycloak_manage_users.sh add-user charlie charlie@aravindahwk.org Charlie789!

# List all users to verify
./keycloak_manage_users.sh list-users

# Test password reset for one user
./keycloak_manage_users.sh reset-password alice NewAlice123!
```

## Batch User Creation Script

If you need to create many users, you can create a batch script:

```bash
#!/bin/bash
# create_multiple_users.sh

USERS=(
  "alice:alice@aravindahwk.org:Pass123"
  "bob:bob@aravindahwk.org:Pass456"
  "charlie:charlie@aravindahwk.org:Pass789"
  "dave:dave@aravindahwk.org:Pass012"
)

for user_data in "${USERS[@]}"; do
  IFS=':' read -r username email password <<< "$user_data"
  ./keycloak_manage_users.sh add-user "$username" "$email" "$password"
  echo "---"
done

echo "All users created! Listing them now:"
./keycloak_manage_users.sh list-users
```

Save this as `create_multiple_users.sh`, make it executable, and run it:
```bash
chmod +x create_multiple_users.sh
./create_multiple_users.sh
```

## Using Created Users with Email Client

Once you've created users with the script, they can immediately use their credentials to:

### IMAP/SMTP Login
- **Username:** john@aravindahwk.org (or just 'john' depending on config)
- **Password:** SecurePass123 (the password you set)

### Email Client Configuration
```
IMAP Server: aravindahwk.org
IMAP Port: 993 (SSL/TLS) or 143 (STARTTLS)
SMTP Server: aravindahwk.org  
SMTP Port: 587 (STARTTLS) or 25
Username: john@aravindahwk.org
Password: SecurePass123
```

## Troubleshooting

### Error: "Domain name is not configured"
Make sure your `conf/silver.yaml` has the domain configured:
```yaml
domains:
  - domain: aravindahwk.org
    dkim-selector: mail
    dkim-key-size: 2048
```

### Error: "Failed to authenticate with Keycloak"
1. Check if Keycloak is running:
   ```bash
   docker ps | grep keycloak
   ```

2. Check Keycloak logs:
   ```bash
   docker logs keycloak-server
   ```

3. Verify Keycloak is accessible:
   ```bash
   curl http://aravindahwk.org:8080/realms/master
   ```

### Error: "User 'john' not found" (when trying to delete/reset)
- The username might be incorrect
- List all users first to see available usernames:
  ```bash
  ./keycloak_manage_users.sh list-users
  ```

### Error: "Failed to create user (HTTP 409)"
- The user already exists
- Either delete the existing user first or use a different username

## Advanced: Using Keycloak Admin Console

You can also manage users via the web interface:

1. **Access Keycloak Admin Console:**
   - URL: `http://aravindahwk.org:8080/admin`
   - Username: `admin`
   - Password: `admin`

2. **Navigate to Users:**
   - Select `silver-mail` realm from the dropdown
   - Click `Users` in the left sidebar
   - Click `Add user` button

3. **Fill in User Details:**
   - Username: john
   - Email: john@aravindahwk.org
   - Email Verified: ON
   - Enabled: ON
   - Click `Create`

4. **Set Password:**
   - Go to `Credentials` tab
   - Click `Set password`
   - Enter password and confirm
   - Set `Temporary` to OFF
   - Click `Save`

## Password Requirements

By default, Keycloak has minimal password requirements. For production:

1. Go to Keycloak Admin Console
2. Select `silver-mail` realm
3. Go to `Authentication` → `Policies` → `Password Policy`
4. Add policies like:
   - Minimum Length: 8
   - Uppercase Characters: 1
   - Lowercase Characters: 1
   - Special Characters: 1
   - Digits: 1

## Integration with Silver Mail

After creating users in Keycloak, they should automatically be able to:

1. **Send emails** via SMTP (port 587)
2. **Receive emails** via IMAP (port 993)
3. **Change their password** via the change-password UI (port 3443)

The mail services will authenticate users against Keycloak automatically.

## Best Practices

1. **Use strong passwords** - At least 12 characters with mixed case, numbers, and symbols
2. **Enable email verification** - Already enabled in the script
3. **Regular backups** - Back up Keycloak data regularly
4. **Monitor user activity** - Check Keycloak logs for suspicious activity
5. **Disable unused accounts** - Remove or disable accounts that are no longer needed

## Need Help?

- Check Keycloak logs: `docker logs keycloak-server`
- Check Silver Mail logs: `docker compose logs -f`
- Review the script source: `cat keycloak_manage_users.sh`
- Test Keycloak connection: `cd ../service && ./test-keycloak-connection.sh`

## Summary of All Commands

```bash
# Add user with password
./keycloak_manage_users.sh add-user john john@domain.com Pass123

# List all users
./keycloak_manage_users.sh list-users

# Get user details
./keycloak_manage_users.sh get-user john

# Reset password
./keycloak_manage_users.sh reset-password john NewPass456

# Delete user
./keycloak_manage_users.sh delete-user john

# Show help
./keycloak_manage_users.sh
```
