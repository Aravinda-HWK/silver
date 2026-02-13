#!/bin/bash

# ============================================
#  Keycloak HTTPS Issue Diagnostic
# ============================================

# Colors
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Keycloak HTTPS Issue Diagnostic Tool                 ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Test 1: Check if Keycloak container is running
echo -e "${YELLOW}[Test 1/6] Checking if Keycloak container is running...${NC}"
if docker ps | grep -q keycloak-server; then
    echo -e "${GREEN}  ✓ Keycloak container is running${NC}"
else
    echo -e "${RED}  ✗ Keycloak container is NOT running${NC}"
    echo -e "${YELLOW}  Fix: Run './scripts/service/restart-keycloak.sh'${NC}"
    exit 1
fi
echo ""

# Test 2: Check container logs for startup
echo -e "${YELLOW}[Test 2/6] Checking if Keycloak started successfully...${NC}"
if docker logs keycloak-server 2>&1 | grep -q "Listening on"; then
    echo -e "${GREEN}  ✓ Keycloak started successfully${NC}"
else
    echo -e "${RED}  ✗ Keycloak may not have started properly${NC}"
    echo -e "${YELLOW}  Check logs: docker logs keycloak-server${NC}"
fi
echo ""

# Test 3: Check port binding
echo -e "${YELLOW}[Test 3/6] Checking port 8080 binding...${NC}"
if docker ps | grep keycloak-server | grep -q "8080"; then
    echo -e "${GREEN}  ✓ Port 8080 is mapped${NC}"
else
    echo -e "${RED}  ✗ Port 8080 is NOT mapped${NC}"
fi
echo ""

# Test 4: Test HTTP connectivity
echo -e "${YELLOW}[Test 4/6] Testing HTTP connectivity...${NC}"
HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null)
if [ "$HTTP_RESPONSE" = "200" ] || [ "$HTTP_RESPONSE" = "302" ] || [ "$HTTP_RESPONSE" = "303" ]; then
    echo -e "${GREEN}  ✓ HTTP connection successful (HTTP $HTTP_RESPONSE)${NC}"
else
    echo -e "${RED}  ✗ HTTP connection failed (HTTP $HTTP_RESPONSE)${NC}"
    echo -e "${YELLOW}  Keycloak may still be starting up...${NC}"
fi
echo ""

# Test 5: Check for HTTPS requirement error
echo -e "${YELLOW}[Test 5/6] Checking for HTTPS requirement...${NC}"
HTTP_CONTENT=$(curl -s http://localhost:8080/ 2>/dev/null)
if echo "$HTTP_CONTENT" | grep -qi "HTTPS required"; then
    echo -e "${RED}  ✗ HTTPS is required (this is the problem!)${NC}"
    echo -e "${YELLOW}  Fix: Run './scripts/service/restart-keycloak.sh'${NC}"
else
    echo -e "${GREEN}  ✓ No HTTPS requirement detected${NC}"
fi
echo ""

# Test 6: Check environment variables
echo -e "${YELLOW}[Test 6/6] Checking Keycloak configuration...${NC}"
KC_HTTP_ENABLED=$(docker inspect keycloak-server 2>/dev/null | grep -o '"KC_HTTP_ENABLED=true"' || echo "")
KC_HOSTNAME_STRICT=$(docker inspect keycloak-server 2>/dev/null | grep -o '"KC_HOSTNAME_STRICT=false"' || echo "")

if [ -n "$KC_HTTP_ENABLED" ]; then
    echo -e "${GREEN}  ✓ KC_HTTP_ENABLED is set to true${NC}"
else
    echo -e "${RED}  ✗ KC_HTTP_ENABLED is NOT set correctly${NC}"
fi

if [ -n "$KC_HOSTNAME_STRICT" ]; then
    echo -e "${GREEN}  ✓ KC_HOSTNAME_STRICT is set to false${NC}"
else
    echo -e "${RED}  ✗ KC_HOSTNAME_STRICT is NOT set correctly${NC}"
fi
echo ""

# Summary and recommendations
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}                          SUMMARY${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""

if echo "$HTTP_CONTENT" | grep -qi "HTTPS required"; then
    echo -e "${RED}❌ HTTPS Issue Detected!${NC}"
    echo ""
    echo -e "${YELLOW}Recommended Fix:${NC}"
    echo "  1. Run: ./scripts/service/restart-keycloak.sh"
    echo "  2. Wait 30 seconds for Keycloak to start"
    echo "  3. Access: http://localhost:8080/admin"
    echo "  4. Use: admin / admin"
    echo ""
    echo -e "${YELLOW}Alternative Fix (if restart doesn't work):${NC}"
    echo "  1. Stop: docker compose -f services/docker-compose.keycloak.yaml down"
    echo "  2. Remove volume: docker volume rm silver_keycloak-data"
    echo "  3. Start: docker compose -f services/docker-compose.keycloak.yaml up -d"
    echo ""
else
    echo -e "${GREEN}✅ No HTTPS issues detected!${NC}"
    echo ""
    echo "You should be able to access Keycloak at:"
    echo "  http://localhost:8080/admin"
    echo ""
    echo "Credentials:"
    echo "  Username: admin"
    echo "  Password: admin"
    echo ""
fi

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "For more help, see: KEYCLOAK_HTTPS_FIX.md"
