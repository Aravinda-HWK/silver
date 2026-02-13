# Keycloak and Shared.db Integration Guide

## Overview

The Keycloak integration for Silver Mail now includes **automatic synchronization** between Keycloak (identity provider) and `shared.db` (mail server database). This ensures that users created in Keycloak can immediately send and receive emails through the Raven IMAP/SMTP server.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User Management Flow                      │
└─────────────────────────────────────────────────────────────┘

  1. User Created in Keycloak
            ↓
  2. Keycloak stores user credentials
            ↓
  3. Script syncs user to shared.db
            ↓
  4. Raven (IMAP/SMTP) can authenticate user
            ↓
  5. User can send/receive emails
```

## Components

### 1. **Keycloak** (Identity Provider)
- Stores user credentials
- Handles authentication
- Manages user attributes
- Location: `keycloak-server` container

### 2. **shared.db** (Mail Server Database)
- SQLite database used by Raven
- Stores user-to-domain mappings
- Enables IMAP/SMTP access
- Location: `/app/data/databases/shared.db` in SMTP container

### 3. **Sync Utilities**
- `shared-db-sync.sh` - Low-level database operations
- `keycloak_manage_users.sh` - Automatically syncs on user add/delete
- `sync-keycloak-to-db.sh` - Bulk synchronization tool

## How It Works

### When You Create a User

```bash
./keycloak_manage_users.sh add-user john john@example.com Pass123
```

**What happens:**
1. ✓ User created in Keycloak realm `silver-mail`
2. ✓ Password set in Keycloak
3. ✓ User automatically added to `shared.db`
4. ✓ User can immediately use IMAP/SMTP with these credentials

### When You Delete a User

```bash
./keycloak_manage_users.sh delete-user john
```

**What happens:**
1. ✓ User deleted from Keycloak
2. ✓ User disabled in `shared.db` (soft delete)
3. ✓ User can no longer access mail services

## Database Schema

### shared.db Structure

```sql
-- Domains table
CREATE TABLE domains (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL UNIQUE,
    enabled INTEGER DEFAULT 1
);

-- Users table
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    domain_id INTEGER NOT NULL,
    enabled INTEGER DEFAULT 1,
    FOREIGN KEY (domain_id) REFERENCES domains(id),
    UNIQUE(username, domain_id)
);
```

## Usage Examples

### 1. Create User (Automatic Sync)

```bash
cd scripts/user

# Add user - automatically syncs to shared.db
./keycloak_manage_users.sh add-user alice alice@example.com Alice123!
```

**Output:**
```
Authenticating with Keycloak...
  ✓ Authentication successful
Creating user 'alice' with email 'alice@example.com'...
✓ User 'alice' created successfully in Keycloak

  - Syncing user to shared.db (Raven)...
  - Adding user to shared.db: alice@example.com
  ✓ User added to shared.db successfully
  ✓ User synced to mail database

✓ Password set successfully

User Details:
  Username: alice
  Email:    alice@example.com
  Status:   Enabled
```

### 2. Bulk Sync Existing Users

If you already have users in Keycloak and need to sync them:

```bash
cd scripts/user

# Sync all Keycloak users to shared.db
./sync-keycloak-to-db.sh
```

**Output:**
```
╔════════════════════════════════════════════════════════════════╗
║     Keycloak to Shared.db Synchronization Tool                ║
╚════════════════════════════════════════════════════════════════╝

Domain: example.com
Realm:  silver-mail

Step 1/3: Authenticating with Keycloak...
  ✓ Authentication successful

Step 2/3: Fetching users from Keycloak...
  - Querying Keycloak for users in realm 'silver-mail'...
  ✓ Found 5 users in Keycloak

Step 3/3: Syncing users to shared.db...
  - Initializing domain in shared.db...
  ✓ Domain initialized successfully
  - Skipping admin user
  - Syncing user: alice@example.com
  ✓ User added to shared.db successfully
  - Syncing user: bob@example.com
  ✓ User added to shared.db successfully
  - Syncing user: charlie@example.com
  ✓ User added to shared.db successfully

════════════════════════════════════════════════════════════════
Synchronization Complete!
════════════════════════════════════════════════════════════════

Summary:
  Total users in Keycloak: 5
  Successfully synced:     3
  Skipped (disabled/admin): 1

✓ All users synced successfully!
```

### 3. List Users in shared.db

```bash
# Using the sync utility
source scripts/utils/shared-db-sync.sh
db_list_users example.com
```

**Output:**
```
username    domain          enabled
----------  --------------  -------
alice       example.com     1
bob         example.com     1
charlie     example.com     1
```

### 4. Manual Database Operations

```bash
# Source the utility
source scripts/utils/shared-db-sync.sh

# Add user manually
db_add_user "dave" "example.com"

# Remove user manually
db_remove_user "dave" "example.com"

# Check if user exists
if db_user_exists "alice" "example.com"; then
    echo "User exists"
fi

# Initialize domain
db_init_domain "example.com"
```

## Setup Process

### During start-silver-keycloak.sh

The setup script automatically:

1. ✓ Starts all services (including SMTP/Raven)
2. ✓ Creates Keycloak realm
3. ✓ Creates Keycloak client
4. ✓ **Initializes domain in shared.db**
5. ✓ Ready to add users

### After Initial Setup

```bash
# 1. Start services
cd scripts/service
./start-silver-keycloak.sh

# 2. Add users
cd ../user
./keycloak_manage_users.sh add-user user1 user1@example.com Pass1
./keycloak_manage_users.sh add-user user2 user2@example.com Pass2
./keycloak_manage_users.sh add-user user3 user3@example.com Pass3

# 3. Verify users can access mail
# Users can now configure their email clients with these credentials
```

## Troubleshooting

### Issue: User created in Keycloak but can't send/receive email

**Solution:** Manually sync the user to shared.db

```bash
source scripts/utils/shared-db-sync.sh
db_add_user "username" "example.com"
```

Or run the bulk sync:

```bash
cd scripts/user
./sync-keycloak-to-db.sh
```

### Issue: Domain not found in database

**Solution:** Initialize the domain

```bash
source scripts/utils/shared-db-sync.sh
db_init_domain "example.com"
```

### Issue: SMTP container not running

**Solution:** Start the services

```bash
cd services
docker compose up -d
```

### Issue: Check if user exists in shared.db

```bash
# Connect to SMTP container and query database
docker exec smtp-server-container sqlite3 /app/data/databases/shared.db \
  "SELECT u.username, d.domain FROM users u 
   JOIN domains d ON u.domain_id = d.id 
   WHERE u.enabled = 1;"
```

## Files Overview

### Core Files

```
scripts/
├── utils/
│   ├── keycloak-auth.sh          # Keycloak API authentication
│   └── shared-db-sync.sh         # Database sync utilities (NEW)
├── user/
│   ├── keycloak_manage_users.sh  # User management (UPDATED)
│   └── sync-keycloak-to-db.sh    # Bulk sync tool (NEW)
└── service/
    └── start-silver-keycloak.sh  # Main setup script (UPDATED)
```

### Key Functions in shared-db-sync.sh

| Function | Purpose |
|----------|---------|
| `db_add_user` | Add user to shared.db |
| `db_remove_user` | Disable user in shared.db |
| `db_list_users` | List all users |
| `db_user_exists` | Check if user exists |
| `db_init_domain` | Initialize domain |
| `check_smtp_container` | Verify container is running |

## Integration Points

### 1. User Creation
- **File:** `keycloak_manage_users.sh`
- **Function:** `add_user()`
- **Action:** Calls `db_add_user()` after Keycloak user creation

### 2. User Deletion
- **File:** `keycloak_manage_users.sh`
- **Function:** `delete_user()`
- **Action:** Calls `db_remove_user()` after Keycloak deletion

### 3. Initial Setup
- **File:** `start-silver-keycloak.sh`
- **Step:** 4.5
- **Action:** Calls `db_init_domain()` during setup

## Testing the Integration

### Complete Test Flow

```bash
# 1. Start services
cd scripts/service
./start-silver-keycloak.sh

# Wait for services to be ready...

# 2. Create test user
cd ../user
./keycloak_manage_users.sh add-user testuser test@example.com TestPass123

# 3. Verify in Keycloak
./keycloak_manage_users.sh get-user testuser

# 4. Verify in shared.db
source ../utils/shared-db-sync.sh
db_list_users example.com

# 5. Test email client connection
# Configure email client with:
#   Username: testuser@example.com
#   Password: TestPass123
#   IMAP: example.com:993
#   SMTP: example.com:587

# 6. Cleanup
./keycloak_manage_users.sh delete-user testuser
```

## Best Practices

1. **Always use the management script** - Don't manually edit shared.db
2. **Run bulk sync after migration** - If moving from Thunder to Keycloak
3. **Backup shared.db regularly** - Important for disaster recovery
4. **Monitor sync status** - Check logs for sync failures
5. **Test after adding users** - Verify email access works

## Migration from Thunder

If you're migrating from Thunder to Keycloak:

```bash
# 1. Export users from Thunder (if possible)
# 2. Create users in Keycloak
# 3. Run bulk sync to update shared.db
cd scripts/user
./sync-keycloak-to-db.sh

# 4. Verify all users are synced
source ../utils/shared-db-sync.sh
db_list_users your-domain.com
```

## Summary

The Keycloak integration now provides **seamless synchronization** between:
- ✓ Keycloak (authentication/identity management)
- ✓ shared.db (mail server user database)
- ✓ Raven (IMAP/SMTP server)

Users created through the management scripts are **immediately ready** to send and receive emails without any manual intervention!
