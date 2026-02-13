#!/bin/bash

# ============================================
#  Test Keycloak Connection
# ============================================

# Colors
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Get domain from config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="$(cd "${SCRIPT_DIR}/../../conf" && pwd)"
CONFIG_FILE="${CONF_DIR}/silver.yaml"

MAIL_DOMAIN=$(grep -m 1 '^\s*-\s*domain:' "$CONFIG_FILE" | sed 's/.*domain:\s*//' | xargs)

if [ -z "$MAIL_DOMAIN" ]; then
    echo -e "${RED}Error: Domain name is not configured in '$CONFIG_FILE'${NC}"
    exit 1
fi

KEYCLOAK_HOST="${MAIL_DOMAIN}"
KEYCLOAK_PORT=8080

echo "Testing Keycloak connection at http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}"
echo ""

# Test 1: Check if Keycloak is responding
echo -n "1. Checking if Keycloak is responding... "
if curl -s "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/realms/master" | grep -q "realm" 2>/dev/null; then
    echo -e "${GREEN}✓ Success${NC}"
else
    echo -e "${RED}✗ Failed${NC}"
    echo "   Keycloak may not be running. Check with: docker ps | grep keycloak"
    exit 1
fi

# Test 2: Check if we can authenticate
echo -n "2. Testing authentication... "
RESPONSE=$(curl -s -X POST \
    "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=admin-cli" \
    -d "username=admin" \
    -d "password=admin" \
    -d "grant_type=password")

if echo "$RESPONSE" | grep -q "access_token"; then
    echo -e "${GREEN}✓ Success${NC}"
    ACCESS_TOKEN=$(echo "$RESPONSE" | grep -o '"access_token":"[^"]*' | sed 's/"access_token":"//')
else
    echo -e "${RED}✗ Failed${NC}"
    echo "   Response: $RESPONSE"
    exit 1
fi

# Test 3: Check if silver-mail realm exists
echo -n "3. Checking if silver-mail realm exists... "
REALM_CHECK=$(curl -s -X GET \
    "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms/silver-mail" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")

if echo "$REALM_CHECK" | grep -q "silver-mail"; then
    echo -e "${GREEN}✓ Success${NC}"
else
    echo -e "${YELLOW}⚠ Not found (this is normal if you haven't run the setup yet)${NC}"
fi

# Test 4: List all realms
echo -n "4. Listing available realms... "
REALMS=$(curl -s -X GET \
    "http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin/realms" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")

if [ -n "$REALMS" ]; then
    echo -e "${GREEN}✓ Success${NC}"
    echo "   Available realms:"
    echo "$REALMS" | grep -o '"realm":"[^"]*"' | sed 's/"realm":"//;s/"//g' | sed 's/^/   - /'
else
    echo -e "${RED}✗ Failed${NC}"
fi

echo ""
echo -e "${GREEN}=== Keycloak Connection Test Complete ===${NC}"
echo ""
echo "Admin Console: http://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/admin"
echo "Username: admin"
echo "Password: admin"
