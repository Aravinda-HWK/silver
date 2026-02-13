#!/bin/bash

# ============================================
#  Keycloak User Management Script
# ============================================
#
# This script helps manage email users in Keycloak for Silver Mail
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

# Source Keycloak authentication utility
source "${SCRIPT_DIR}/../utils/keycloak-auth.sh"

# Source shared database sync utility
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

# ============================================
# Function: Display usage
# ============================================
usage() {
    cat <<EOF
${CYAN}Keycloak User Management for Silver Mail${NC}

Usage: $0 <command> [options]

Commands:
  add-user <username> <email> [password]    Add a new user
  delete-user <username>                     Delete a user
  reset-password <username> <new-password>   Reset user password
  list-users                                 List all users
  get-user <username>                        Get user details
  enable-user <username>                     Enable a user account
  disable-user <username>                    Disable a user account

Examples:
  $0 add-user john john@${MAIL_DOMAIN} mypassword
  $0 delete-user john
  $0 reset-password john newpassword123
  $0 list-users

EOF
}

# ============================================
# Function: Add user
# ============================================
add_user() {
    local username="$1"
    local email="$2"
    local password="$3"

    if [ -z "$username" ] || [ -z "$email" ]; then
        echo -e "${RED}Error: Username and email are required${NC}"
        echo "Usage: $0 add-user <username> <email> [password]"
        exit 1
    fi

    # Authenticate with Keycloak
    if ! keycloak_authenticate "$KEYCLOAK_HOST" "$KEYCLOAK_PORT" "master"; then
        exit 1
    fi

    # Create user
    echo "Creating user '${username}' with email '${email}'..."
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST \
        "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}" \
        -d "{
            \"username\": \"${username}\",
            \"email\": \"${email}\",
            \"enabled\": true,
            \"emailVerified\": true
        }")

    local body
    local status
    body=$(echo "$response" | head -n -1)
    status=$(echo "$response" | tail -n1)

    if [ "$status" -ne 201 ] && [ "$status" -ne 204 ]; then
        echo -e "${RED}✗ Failed to create user (HTTP $status)${NC}"
        echo "Response: $body"
        exit 1
    fi

    echo -e "${GREEN}✓ User '${username}' created successfully in Keycloak${NC}"

    # Add user to shared.db (for Raven IMAP/SMTP)
    echo ""
    echo "  - Syncing user to shared.db (Raven)..."
    if db_add_user "$username" "$MAIL_DOMAIN"; then
        echo -e "${GREEN}  ✓ User synced to mail database${NC}"
    else
        echo -e "${YELLOW}  ⚠ Warning: User created in Keycloak but failed to sync to mail database${NC}"
        echo -e "${YELLOW}  You may need to manually add the user to shared.db${NC}"
    fi

    # Set password if provided
    if [ -n "$password" ]; then
        # Get user ID
        local user_response
        user_response=$(curl -s -X GET \
            "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users?username=${username}" \
            -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}")

        local user_id
        user_id=$(echo "$user_response" | grep -o '"id":"[^"]*"' | head -n1 | sed 's/"id":"//;s/"//')

        if [ -n "$user_id" ]; then
            # Set password
            local pwd_response
            pwd_response=$(curl -s -w "\n%{http_code}" -X PUT \
                "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users/${user_id}/reset-password" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}" \
                -d "{
                    \"type\": \"password\",
                    \"value\": \"${password}\",
                    \"temporary\": false
                }")

            local pwd_status
            pwd_status=$(echo "$pwd_response" | tail -n1)

            if [ "$pwd_status" -eq 204 ] || [ "$pwd_status" -eq 200 ]; then
                echo -e "${GREEN}✓ Password set successfully${NC}"
            else
                echo -e "${YELLOW}⚠ Warning: User created but failed to set password${NC}"
            fi
        fi
    fi

    echo ""
    echo -e "${CYAN}User Details:${NC}"
    echo "  Username: ${username}"
    echo "  Email:    ${email}"
    echo "  Status:   Enabled"
}

# ============================================
# Function: Delete user
# ============================================
delete_user() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username is required${NC}"
        echo "Usage: $0 delete-user <username>"
        exit 1
    fi

    # Authenticate with Keycloak
    if ! keycloak_authenticate "$KEYCLOAK_HOST" "$KEYCLOAK_PORT" "master"; then
        exit 1
    fi

    # Get user ID
    local user_response
    user_response=$(curl -s -X GET \
        "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users?username=${username}" \
        -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}")

    local user_id
    user_id=$(echo "$user_response" | grep -o '"id":"[^"]*"' | head -n1 | sed 's/"id":"//;s/"//')

    if [ -z "$user_id" ]; then
        echo -e "${RED}✗ User '${username}' not found${NC}"
        exit 1
    fi

    # Delete user
    local response
    response=$(curl -s -w "\n%{http_code}" -X DELETE \
        "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users/${user_id}" \
        -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}")

    local status
    status=$(echo "$response" | tail -n1)

    if [ "$status" -eq 204 ] || [ "$status" -eq 200 ]; then
        echo -e "${GREEN}✓ User '${username}' deleted from Keycloak${NC}"
        
        # Remove user from shared.db (for Raven IMAP/SMTP)
        echo ""
        echo "  - Syncing deletion to shared.db (Raven)..."
        if db_remove_user "$username" "$MAIL_DOMAIN"; then
            echo -e "${GREEN}  ✓ User removed from mail database${NC}"
        else
            echo -e "${YELLOW}  ⚠ Warning: User deleted from Keycloak but failed to remove from mail database${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to delete user (HTTP $status)${NC}"
        exit 1
    fi
}

# ============================================
# Function: Reset password
# ============================================
reset_password() {
    local username="$1"
    local new_password="$2"

    if [ -z "$username" ] || [ -z "$new_password" ]; then
        echo -e "${RED}Error: Username and new password are required${NC}"
        echo "Usage: $0 reset-password <username> <new-password>"
        exit 1
    fi

    # Authenticate with Keycloak
    if ! keycloak_authenticate "$KEYCLOAK_HOST" "$KEYCLOAK_PORT" "master"; then
        exit 1
    fi

    # Get user ID
    local user_response
    user_response=$(curl -s -X GET \
        "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users?username=${username}" \
        -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}")

    local user_id
    user_id=$(echo "$user_response" | grep -o '"id":"[^"]*"' | head -n1 | sed 's/"id":"//;s/"//')

    if [ -z "$user_id" ]; then
        echo -e "${RED}✗ User '${username}' not found${NC}"
        exit 1
    fi

    # Reset password
    local response
    response=$(curl -s -w "\n%{http_code}" -X PUT \
        "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users/${user_id}/reset-password" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}" \
        -d "{
            \"type\": \"password\",
            \"value\": \"${new_password}\",
            \"temporary\": false
        }")

    local status
    status=$(echo "$response" | tail -n1)

    if [ "$status" -eq 204 ] || [ "$status" -eq 200 ]; then
        echo -e "${GREEN}✓ Password reset successfully for user '${username}'${NC}"
    else
        echo -e "${RED}✗ Failed to reset password (HTTP $status)${NC}"
        exit 1
    fi
}

# ============================================
# Function: List users
# ============================================
list_users() {
    # Authenticate with Keycloak
    if ! keycloak_authenticate "$KEYCLOAK_HOST" "$KEYCLOAK_PORT" "master"; then
        exit 1
    fi

    # Get users
    local response
    response=$(curl -s -X GET \
        "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users" \
        -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}")

    echo -e "${CYAN}Users in realm '${REALM_NAME}':${NC}"
    echo ""
    
    # Parse and display users (simple formatting)
    echo "$response" | grep -o '"username":"[^"]*"' | sed 's/"username":"//;s/"//' | while read -r username; do
        local email=$(echo "$response" | grep -A5 "\"username\":\"${username}\"" | grep -o '"email":"[^"]*"' | head -n1 | sed 's/"email":"//;s/"//')
        local enabled=$(echo "$response" | grep -A5 "\"username\":\"${username}\"" | grep -o '"enabled":[^,]*' | head -n1 | sed 's/"enabled"://')
        
        if [ "$enabled" = "true" ]; then
            status="${GREEN}✓ Enabled${NC}"
        else
            status="${RED}✗ Disabled${NC}"
        fi
        
        echo -e "  • ${username} <${email}> - ${status}"
    done
}

# ============================================
# Function: Get user details
# ============================================
get_user() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username is required${NC}"
        echo "Usage: $0 get-user <username>"
        exit 1
    fi

    # Authenticate with Keycloak
    if ! keycloak_authenticate "$KEYCLOAK_HOST" "$KEYCLOAK_PORT" "master"; then
        exit 1
    fi

    # Get user
    local response
    response=$(curl -s -X GET \
        "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/${REALM_NAME}/users?username=${username}" \
        -H "Authorization: Bearer ${KEYCLOAK_ACCESS_TOKEN}")

    if echo "$response" | grep -q "\"username\":\"${username}\""; then
        echo -e "${CYAN}User Details:${NC}"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    else
        echo -e "${RED}✗ User '${username}' not found${NC}"
        exit 1
    fi
}

# ============================================
# Main script logic
# ============================================

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
    add-user)
        add_user "$@"
        ;;
    delete-user)
        delete_user "$@"
        ;;
    reset-password)
        reset_password "$@"
        ;;
    list-users)
        list_users
        ;;
    get-user)
        get_user "$@"
        ;;
    *)
        echo -e "${RED}Error: Unknown command '${COMMAND}'${NC}"
        echo ""
        usage
        exit 1
        ;;
esac
