#!/bin/bash

# ============================================
#  Restart Keycloak Service
# ============================================

# Colors
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$(cd "${SCRIPT_DIR}/../../services" && pwd)"

echo -e "${YELLOW}Restarting Keycloak service...${NC}"

# Stop Keycloak
echo "  - Stopping Keycloak..."
(cd "${SERVICES_DIR}" && docker compose -f docker-compose.keycloak.yaml down)

# Wait a moment
sleep 2

# Start Keycloak
echo "  - Starting Keycloak..."
(cd "${SERVICES_DIR}" && docker compose -f docker-compose.keycloak.yaml up -d)

# Wait for Keycloak to be ready
echo "  - Waiting for Keycloak to be ready..."
sleep 5

MAX_WAIT=60
WAIT_COUNT=0

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if docker logs keycloak-server 2>&1 | grep -q "Listening on"; then
        echo -e "${GREEN}  ✓ Keycloak is ready${NC}"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
    echo -n "."
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo -e "${RED}\n  ✗ Keycloak did not start in time${NC}"
    echo -e "${YELLOW}  Check logs with: docker logs keycloak-server${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Keycloak restarted successfully${NC}"
echo ""
echo "Access Keycloak at: http://localhost:8080"
echo "Admin Console: http://localhost:8080/admin"
echo "Username: admin"
echo "Password: admin"
