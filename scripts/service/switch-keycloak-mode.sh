#!/bin/bash

# ============================================
#  Switch Keycloak Mode (Development/Production)
# ============================================

# Colors
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$(cd "${SCRIPT_DIR}/../../services" && pwd)"
CONF_DIR="$(cd "${SCRIPT_DIR}/../../conf" && pwd)"
CONFIG_FILE="${CONF_DIR}/silver.yaml"

# Extract domain
DOMAIN=$(grep -m 1 '^\s*-\s*domain:' "$CONFIG_FILE" | sed 's/.*domain:\s*//' | xargs)

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain name is not configured in '$CONFIG_FILE'${NC}"
    exit 1
fi

# Display usage
usage() {
    cat <<EOF
${CYAN}Keycloak Mode Switcher${NC}

Usage: $0 [development|production|status]

Commands:
  development   Switch to development mode (HTTP, embedded H2 database)
  production    Switch to production mode (HTTPS, PostgreSQL, certbot certs)
  status        Show current mode and configuration

Examples:
  $0 development   # Start Keycloak in development mode
  $0 production    # Start Keycloak in production mode
  $0 status        # Check current status

EOF
}

# Check current mode
check_status() {
    echo -e "${CYAN}Keycloak Status${NC}"
    echo "=================="
    echo ""
    
    # Check if development container is running
    if docker ps | grep -q "keycloak-server"; then
        echo -e "Mode: ${GREEN}Development${NC}"
        echo "Container: keycloak-server"
        echo "HTTP: http://${DOMAIN}:8080"
        echo "Admin: http://${DOMAIN}:8080/admin"
        echo "Database: Embedded H2"
    # Check if production container is running
    elif docker ps | grep -q "keycloak-server-production"; then
        echo -e "Mode: ${GREEN}Production${NC}"
        echo "Container: keycloak-server-production"
        echo "HTTPS: https://${DOMAIN}:8443"
        echo "Admin: https://${DOMAIN}:8443/admin"
        echo "Database: PostgreSQL"
        
        # Check if certificates exist
        CERT_PATH="${SERVICES_DIR}/silver-config/certbot/keys/etc/live/${DOMAIN}"
        if [ -d "$CERT_PATH" ]; then
            echo -e "Certificates: ${GREEN}✓ Found${NC} (${CERT_PATH})"
        else
            echo -e "Certificates: ${RED}✗ Not found${NC} (${CERT_PATH})"
        fi
    else
        echo -e "Mode: ${YELLOW}Not running${NC}"
    fi
    echo ""
}

# Switch to development mode
switch_to_development() {
    echo -e "${YELLOW}Switching to Development Mode...${NC}"
    echo ""
    
    # Stop production if running
    echo "  - Stopping production mode (if running)..."
    (cd "${SERVICES_DIR}" && docker compose -f docker-compose.keycloak-production.yaml down 2>/dev/null)
    
    # Start development
    echo "  - Starting development mode..."
    (cd "${SERVICES_DIR}" && docker compose -f docker-compose.keycloak.yaml up -d)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Switched to development mode${NC}"
        echo ""
        echo "Keycloak is starting..."
        echo "  - HTTP: http://${DOMAIN}:8080"
        echo "  - Admin: http://${DOMAIN}:8080/admin"
        echo "  - Username: admin"
        echo "  - Password: admin"
        echo ""
        echo "Wait about 30 seconds for Keycloak to start."
    else
        echo -e "${RED}  ✗ Failed to start development mode${NC}"
        exit 1
    fi
}

# Switch to production mode
switch_to_production() {
    echo -e "${YELLOW}Switching to Production Mode...${NC}"
    echo ""
    
    # Check if certificates exist
    CERT_PATH="${SERVICES_DIR}/silver-config/certbot/keys/etc/live/${DOMAIN}"
    if [ ! -d "$CERT_PATH" ]; then
        echo -e "${RED}✗ Error: SSL certificates not found at ${CERT_PATH}${NC}"
        echo ""
        echo "You need to generate certificates first using certbot."
        echo "The certificates should be at: ${CERT_PATH}"
        echo ""
        echo -e "${YELLOW}To generate certificates:${NC}"
        echo "  1. Ensure your domain DNS points to this server"
        echo "  2. Run certbot or let Silver's certbot container generate them"
        echo "  3. Verify certificates exist at the path above"
        exit 1
    fi
    
    echo -e "${GREEN}  ✓ SSL certificates found${NC}"
    
    # Check for environment variables
    if [ -z "$KEYCLOAK_DB_PASSWORD" ]; then
        echo -e "${YELLOW}  ⚠ Warning: KEYCLOAK_DB_PASSWORD not set${NC}"
        echo "  Using default password (not recommended for production!)"
    fi
    
    if [ -z "$KEYCLOAK_ADMIN_PASSWORD" ]; then
        echo -e "${YELLOW}  ⚠ Warning: KEYCLOAK_ADMIN_PASSWORD not set${NC}"
        echo "  Using default admin password (not recommended for production!)"
    fi
    
    # Stop development if running
    echo "  - Stopping development mode (if running)..."
    (cd "${SERVICES_DIR}" && docker compose -f docker-compose.keycloak.yaml down 2>/dev/null)
    
    # Start production
    echo "  - Starting production mode..."
    export KEYCLOAK_HOSTNAME="$DOMAIN"
    (cd "${SERVICES_DIR}" && docker compose -f docker-compose.keycloak-production.yaml up -d)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Switched to production mode${NC}"
        echo ""
        echo "Keycloak is starting..."
        echo "  - HTTPS: https://${DOMAIN}:8443"
        echo "  - Admin: https://${DOMAIN}:8443/admin"
        echo "  - Username: admin (or custom if KEYCLOAK_ADMIN is set)"
        echo "  - Password: Check KEYCLOAK_ADMIN_PASSWORD or default"
        echo ""
        echo "Wait about 60-90 seconds for Keycloak to start."
        echo ""
        echo -e "${YELLOW}⚠ Production Checklist:${NC}"
        echo "  1. Change default admin password immediately"
        echo "  2. Set KEYCLOAK_DB_PASSWORD environment variable"
        echo "  3. Set KEYCLOAK_ADMIN_PASSWORD environment variable"
        echo "  4. Configure firewall to allow ports 8080/8443"
        echo "  5. Set up database backups"
    else
        echo -e "${RED}  ✗ Failed to start production mode${NC}"
        exit 1
    fi
}

# Main logic
case "${1:-}" in
    development|dev)
        switch_to_development
        ;;
    production|prod)
        switch_to_production
        ;;
    status)
        check_status
        ;;
    *)
        usage
        exit 1
        ;;
esac
