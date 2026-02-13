#!/bin/bash

# ============================================
#  Sync Keycloak Users to Shared Database
# ============================================
#
# This script synchronizes all users from Keycloak to the shared.db
# used by Raven (IMAP/SMTP server)
#

# Colors
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$(cd "${SCRIPT_DIR}/../../conf" && pwd)"
CONFIG_FILE="${CONF_DIR}/silver.yaml"

# Source utilities
source "${SCRIPT_DIR}/../utils/keycloak-auth.sh"
source "${SCRIPT_DIR}/../utils/shared-db-sync.sh"

# Extract domain
MAIL_DOMAIN=$(grep -m 1 '^\s*-\s*domain:' "$CONFIG_FILE" | sed 's/.*domain:\s*//' | xargs)

if [ -z "$MAIL_DOMAIN" ]; then
    echo -e "${RED}Error: Domain name is not configured in '$CONFIG_FILE'${NC}"
    exit 1
fi

KEYCLOAK_HOST="${MAIL_DOMAIN}"
KEYCLOAK_PORT=8080
REALM_NAME="silver-mail"

echo -e "${CYAN}"
cat <<'EOF'
╔════════════════════════════════════════════════════════════════╗
║     Keycloak to Shared.db Synchronization Tool                ║
╚════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
echo -e "Domain: ${GREEN}${MAIL_DOMAIN}${NC}"
echo -e "Realm:  ${GREEN}${REALM_NAME}${NC}"
echo ""

# ============================================
# Step 1: Authenticate with Keycloak
# ============================================
echo -e "${YELLOW}Step 1/3: Authenticating with Keycloak...${NC}"
if ! keycloak_authenticate "$KEYCLOAK_HOST" "$KEYCLOAK_PORT" "master"; then
    exit 1
fi

# ============================================
# Step 2: Get users from Keycloak
# ============================================
echo -e "\n${YELLOW}Step 2/3: Fetching users from Keycloak...${NC}"
echo "  - Querying Keycloak for users in realm '${REALM_NAME}'..."

USERS_JSON=$(curl -s -X GET \
    "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users" \
    -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}")

if [ -z "$USERS_JSON" ] || echo "$USERS_JSON" | grep -q "error"; then
    echo -e "${RED}✗ Failed to fetch users from Keycloak${NC}"
    echo "Response: $USERS_JSON"
    exit 1
fi

# Count users
USER_COUNT=$(echo "$USERS_JSON" | grep -o '"username":"[^"]*"' | wc -l | tr -d ' ')
echo -e "${GREEN}  ✓ Found ${USER_COUNT} users in Keycloak${NC}"

if [ "$USER_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}  No users to sync${NC}"
    exit 0
fi

# ============================================
# Step 3: Sync users to shared.db
# ============================================
echo -e "\n${YELLOW}Step 3/3: Syncing users to shared.db...${NC}"

# Initialize domain first
echo "  - Initializing domain in shared.db..."
if ! db_init_domain "$MAIL_DOMAIN"; then
    echo -e "${RED}✗ Failed to initialize domain${NC}"
    exit 1
fi

# Parse and sync each user
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

echo "$USERS_JSON" | grep -o '"username":"[^"]*"' | sed 's/"username":"//;s/"//' | while read -r username; do
    # Skip admin user
    if [ "$username" = "admin" ]; then
        echo "  - Skipping admin user"
        continue
    fi
    
    # Check if user is enabled
    ENABLED=$(echo "$USERS_JSON" | grep -A10 "\"username\":\"${username}\"" | grep -o '"enabled":[^,]*' | head -n1 | sed 's/"enabled"://')
    
    if [ "$ENABLED" != "true" ]; then
        echo "  - Skipping disabled user: ${username}"
        ((SKIP_COUNT++))
        continue
    fi
    
    echo "  - Syncing user: ${username}@${MAIL_DOMAIN}"
    
    if db_add_user "$username" "$MAIL_DOMAIN"; then
        ((SUCCESS_COUNT++))
    else
        ((FAIL_COUNT++))
    fi
done

# ============================================
# Summary
# ============================================
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Synchronization Complete!${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Summary:"
echo "  Total users in Keycloak: ${USER_COUNT}"
echo -e "  ${GREEN}Successfully synced:     ${SUCCESS_COUNT}${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "  ${RED}Failed:                  ${FAIL_COUNT}${NC}"
fi
if [ $SKIP_COUNT -gt 0 ]; then
    echo -e "  ${YELLOW}Skipped (disabled/admin): ${SKIP_COUNT}${NC}"
fi
echo ""

# Verify by listing users in shared.db
echo -e "${YELLOW}Users in shared.db:${NC}"
db_list_users "$MAIL_DOMAIN"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠ Some users failed to sync. Check the output above for details.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All users synced successfully!${NC}"
