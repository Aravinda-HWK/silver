#!/bin/bash

# ============================================
#  Silver Mail Production Setup (Keycloak with HTTPS)
# ============================================

# Colors
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$(cd "${SCRIPT_DIR}/../../services" && pwd)"
CONF_DIR="$(cd "${SCRIPT_DIR}/../../conf" && pwd)"
CONFIG_FILE="${CONF_DIR}/silver.yaml"
ENV_FILE="${SERVICES_DIR}/.env.production"

# ASCII Banner
echo -e "${CYAN}"
cat <<'EOF'
   SSSSSSSSSSSSSSS   iiii  lllllll                                                              
 SS:::::::::::::::S i::::i l:::::l                                                              
S:::::SSSSSS::::::S  iiii  l:::::l                                                              
S:::::S     SSSSSSS        l:::::l                                                              
S:::::S            iiiiiii  l::::lvvvvvvv           vvvvvvv eeeeeeeeeeee    rrrrr   rrrrrrrrr   
S:::::S            i::::i  l::::l v:::::v         v:::::vee::::::::::::ee  r::::rrr:::::::::r  
 S::::SSSS          i::::i  l::::l  v:::::v       v:::::ve::::::eeeee:::::eer:::::::::::::::::r 
  SS::::::SSSSS     i::::i  l::::l   v:::::v     v:::::ve::::::e     e:::::err::::::rrrrr::::::r
    SSS::::::::SS   i::::i  l::::l    v:::::v   v:::::v e:::::::eeeee::::::e r:::::r     r:::::r
       SSSSSS::::S  i::::i  l::::l     v:::::v v:::::v  e:::::::::::::::::e  r:::::r     rrrrrrr
            S:::::S i::::i  l::::l      v:::::v:::::v   e::::::eeeeeeeeeee   r:::::r            
            S:::::S i::::i  l::::l       v:::::::::v    e:::::::e            r:::::r            
SSSSSSS     S:::::Si::::::il::::::l       v:::::::v     e::::::::e           r:::::r            
S::::::SSSSSS:::::Si::::::il::::::l        v:::::v       e::::::::eeeeeeee   r:::::r            
S:::::::::::::::SS i::::::il::::::l         v:::v         ee:::::::::::::e   r:::::r            
 SSSSSSSSSSSSSSS   iiiiiiiillllllll          vvv            eeeeeeeeeeeeee   rrrrrrr            
                                                                                                 
EOF
echo -e "${NC}"

echo ""
echo -e " 🚀 ${GREEN}Silver Mail Production Setup (Keycloak with HTTPS)${NC}"
echo "---------------------------------------------"

# ================================
# Step 1: Domain Configuration
# ================================
echo -e "\n${YELLOW}Step 1/7: Validating domain configuration${NC}"

# Extract primary domain from silver.yaml
MAIL_DOMAIN=$(grep -m 1 '^\s*-\s*domain:' "$CONFIG_FILE" | sed 's/.*domain:\s*//' | xargs)

if [ -z "$MAIL_DOMAIN" ]; then
	echo -e "${RED}✗ Error: Domain name not configured in '$CONFIG_FILE'${NC}"
	exit 1
fi

echo -e "  Domain: ${GREEN}${MAIL_DOMAIN}${NC}"

if ! [[ "$MAIL_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
	echo -e "${RED}✗ Warning: '${MAIL_DOMAIN}' does not look like a valid domain name.${NC}"
	exit 1
fi

# ================================
# Step 2: SSL Certificate Validation
# ================================
echo -e "\n${YELLOW}Step 2/7: Validating SSL certificates${NC}"

CERT_PATH="${SERVICES_DIR}/silver-config/certbot/keys/etc/live/${MAIL_DOMAIN}"

if [ ! -d "$CERT_PATH" ]; then
	echo -e "${RED}✗ SSL certificates not found at: ${CERT_PATH}${NC}"
	echo ""
	echo "You need to generate SSL certificates first."
	echo ""
	echo -e "${YELLOW}To generate certificates:${NC}"
	echo "  1. Ensure DNS for ${MAIL_DOMAIN} points to this server"
	echo "  2. Run: cd services/config-scripts && ./gen-certbot-certs.sh"
	echo "  3. Wait for certificate generation to complete"
	echo "  4. Re-run this script"
	exit 1
fi

# Check individual certificate files
required_files=("fullchain.pem" "privkey.pem" "cert.pem" "chain.pem")
all_files_exist=true

for file in "${required_files[@]}"; do
	if [ -f "${CERT_PATH}/${file}" ]; then
		echo -e "  ✓ ${file} found"
	else
		echo -e "  ${RED}✗ ${file} missing${NC}"
		all_files_exist=false
	fi
done

if [ "$all_files_exist" = false ]; then
	echo -e "${RED}✗ Some certificate files are missing${NC}"
	exit 1
fi

# Check certificate expiry
cert_expiry=$(openssl x509 -enddate -noout -in "${CERT_PATH}/cert.pem" 2>/dev/null | cut -d= -f2)
if [ -n "$cert_expiry" ]; then
	echo -e "  ${GREEN}✓ Certificate expires: ${cert_expiry}${NC}"
else
	echo -e "  ${YELLOW}⚠ Could not read certificate expiry${NC}"
fi

# ================================
# Step 3: Environment Variables
# ================================
echo -e "\n${YELLOW}Step 3/7: Configuring production environment${NC}"

# Create/update .env.production file
cat > "$ENV_FILE" <<EOF
# Silver Mail Production Environment Variables
# Generated: $(date)

# Domain Configuration
KEYCLOAK_HOSTNAME=${MAIL_DOMAIN}
DOMAIN=${MAIL_DOMAIN}

# Keycloak Admin Credentials
# ⚠️ CHANGE THESE IMMEDIATELY AFTER FIRST LOGIN!
KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-$(openssl rand -base64 32)}

# Keycloak Database Credentials
KEYCLOAK_DB_PASSWORD=${KEYCLOAK_DB_PASSWORD:-$(openssl rand -base64 32)}

# SeaweedFS S3 Credentials (if needed)
# S3_ACCESS_KEY=${S3_ACCESS_KEY:-}
# S3_SECRET_KEY=${S3_SECRET_KEY:-}

# PostgreSQL Configuration
POSTGRES_DB=keycloak
POSTGRES_USER=keycloak
POSTGRES_PASSWORD=${KEYCLOAK_DB_PASSWORD}
EOF

chmod 600 "$ENV_FILE"
echo -e "${GREEN}  ✓ Environment file created: ${ENV_FILE}${NC}"

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Display credentials securely
echo ""
echo -e "${CYAN}  Production Credentials (SAVE THESE SECURELY):${NC}"
echo "  =================================================="
echo "  Keycloak Admin Username: ${KEYCLOAK_ADMIN}"
echo "  Keycloak Admin Password: ${KEYCLOAK_ADMIN_PASSWORD}"
echo "  Database Password: [hidden - check ${ENV_FILE}]"
echo "  =================================================="
echo ""
echo -e "${RED}  ⚠️  IMPORTANT: Save these credentials now!${NC}"
echo -e "${RED}  ⚠️  Change the admin password after first login!${NC}"
echo ""

read -p "Press Enter to continue after saving credentials..."

# ================================
# Step 4: /etc/hosts Configuration
# ================================
echo -e "\n${YELLOW}Step 4/7: Updating /etc/hosts for local testing${NC}"

if grep -q "[[:space:]]${MAIL_DOMAIN}" /etc/hosts; then
	sudo sed -i.bak "/^[^#]*[[:space:]]${MAIL_DOMAIN}\([[:space:]]\|$\)/s/^.*[[:space:]]${MAIL_DOMAIN}\([[:space:]]\|$\).*/127.0.0.1   ${MAIL_DOMAIN}/" /etc/hosts
	echo -e "${GREEN}  ✓ Updated /etc/hosts${NC}"
else
	echo "127.0.0.1   ${MAIL_DOMAIN}" | sudo tee -a /etc/hosts >/dev/null
	echo -e "${GREEN}  ✓ Added ${MAIL_DOMAIN} to /etc/hosts${NC}"
fi

# ================================
# Step 5: Docker Services Setup
# ================================
echo -e "\n${YELLOW}Step 5/7: Starting Docker services${NC}"

# Check SeaweedFS configuration
SEAWEEDFS_CONFIG="${SERVICES_DIR}/seaweedfs/s3-config.json"
SEAWEEDFS_EXAMPLE="${SERVICES_DIR}/seaweedfs/s3-config.json.example"

if [ ! -f "$SEAWEEDFS_CONFIG" ]; then
	echo "  - Creating SeaweedFS configuration..."
	if [ -f "$SEAWEEDFS_EXAMPLE" ]; then
		cp "$SEAWEEDFS_EXAMPLE" "$SEAWEEDFS_CONFIG"
		echo -e "${YELLOW}  ⚠ Using example S3 config. Update ${SEAWEEDFS_CONFIG} for production!${NC}"
	fi
fi

# Stop development mode if running
echo "  - Stopping development mode (if running)..."
(cd "${SERVICES_DIR}" && docker compose -f docker-compose.keycloak.yaml down 2>/dev/null)

# Start SeaweedFS
echo "  - Starting SeaweedFS blob storage..."
(cd "${SERVICES_DIR}" && docker compose -f docker-compose.seaweedfs.yaml up -d)
if [ $? -ne 0 ]; then
	echo -e "${RED}✗ SeaweedFS failed to start${NC}"
	exit 1
fi
echo -e "${GREEN}  ✓ SeaweedFS started${NC}"

# Start Keycloak Production
echo "  - Starting Keycloak (HTTPS production mode)..."
(cd "${SERVICES_DIR}" && docker compose --env-file .env.production -f docker-compose.keycloak-production.yaml up -d)
if [ $? -ne 0 ]; then
	echo -e "${RED}✗ Keycloak production failed to start${NC}"
	echo "  Check logs: docker logs keycloak-server-production"
	exit 1
fi
echo -e "${GREEN}  ✓ Keycloak production started${NC}"

# Wait for Keycloak to be ready
echo "  - Waiting for Keycloak to be ready (this may take 60-90 seconds)..."
KEYCLOAK_HOST="${MAIL_DOMAIN}"
KEYCLOAK_PORT=8443
MAX_WAIT=180
WAIT_COUNT=0

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
	if curl -s -f -k "https://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/health/ready" > /dev/null 2>&1 || \
	   curl -s -k "https://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}/realms/master" | grep -q "realm" 2>/dev/null; then
		echo -e "\n${GREEN}  ✓ Keycloak is ready${NC}"
		break
	fi
	sleep 3
	WAIT_COUNT=$((WAIT_COUNT + 3))
	echo -n "."
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
	echo -e "\n${RED}✗ Keycloak did not become ready${NC}"
	echo "  Check logs: docker logs keycloak-server-production"
	exit 1
fi

# Start main Silver mail services
echo "  - Starting Silver mail services..."
(cd "${SERVICES_DIR}" && docker compose up -d)
if [ $? -ne 0 ]; then
	echo -e "${RED}✗ Silver mail services failed to start${NC}"
	exit 1
fi
echo -e "${GREEN}  ✓ Silver mail services started${NC}"

sleep 2

# ================================
# Step 6: Keycloak Realm Setup
# ================================
echo -e "\n${YELLOW}Step 6/7: Configuring Keycloak realm${NC}"

# Source Keycloak authentication utility
source "${SCRIPT_DIR}/../utils/keycloak-auth.sh"

# Authenticate with Keycloak (using HTTPS)
KEYCLOAK_URL="https://${KEYCLOAK_HOST}:${KEYCLOAK_PORT}"
export KEYCLOAK_INSECURE="true"  # For self-signed or local certs

if ! keycloak_authenticate "$KEYCLOAK_HOST" "$KEYCLOAK_PORT" "master" "$KEYCLOAK_ADMIN" "$KEYCLOAK_ADMIN_PASSWORD"; then
	echo -e "${RED}✗ Failed to authenticate with Keycloak${NC}"
	echo "  Check credentials and Keycloak logs"
	exit 1
fi

# Create Silver Mail realm
REALM_NAME="silver-mail"
if ! keycloak_create_realm "$KEYCLOAK_HOST" "$KEYCLOAK_PORT" "$KEYCLOAK_ACCESS_TOKEN" "$REALM_NAME" "Silver Mail"; then
	exit 1
fi

# Create client
CLIENT_ID="silver-mail-client"
if ! keycloak_create_client "$KEYCLOAK_HOST" "$KEYCLOAK_PORT" "$REALM_NAME" "$KEYCLOAK_ACCESS_TOKEN" "$CLIENT_ID" "Silver Mail Client"; then
	exit 1
fi

echo -e "${GREEN}  ✓ Keycloak realm configured${NC}"

# ================================
# Step 7: Database Initialization
# ================================
echo -e "\n${YELLOW}Step 7/7: Initializing mail database${NC}"

source "${SCRIPT_DIR}/../utils/shared-db-sync.sh"
if db_init_domain "$MAIL_DOMAIN"; then
	echo -e "${GREEN}  ✓ Mail database initialized${NC}"
else
	echo -e "${RED}✗ Failed to initialize mail database${NC}"
	exit 1
fi

# ================================
# Success Summary
# ================================
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ Silver Mail Production Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Access Points:${NC}"
echo "  • Keycloak Admin: https://${MAIL_DOMAIN}:8443/admin"
echo "  • Keycloak Realm: https://${MAIL_DOMAIN}:8443/realms/silver-mail"
echo "  • IMAP (SSL): ${MAIL_DOMAIN}:993"
echo "  • SMTP (TLS): ${MAIL_DOMAIN}:587"
echo ""
echo -e "${CYAN}Credentials:${NC}"
echo "  • Admin User: ${KEYCLOAK_ADMIN}"
echo "  • Admin Pass: [Check ${ENV_FILE}]"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Access Keycloak admin panel"
echo "  2. Change the default admin password immediately"
echo "  3. Create email users: ${SCRIPT_DIR}/../user/keycloak_manage_users.sh"
echo "  4. Test email login via IMAP/SMTP"
echo "  5. Set up automated certificate renewal"
echo ""
echo -e "${YELLOW}Important Files:${NC}"
echo "  • Environment: ${ENV_FILE}"
echo "  • Certificates: ${CERT_PATH}"
echo "  • Database: ${SERVICES_DIR}/silver-config/raven/data/databases/shared.db"
echo ""
echo -e "${RED}Security Reminders:${NC}"
echo "  ⚠️  Change default passwords immediately"
echo "  ⚠️  Keep ${ENV_FILE} secure (chmod 600)"
echo "  ⚠️  Set up database backups"
echo "  ⚠️  Configure firewall rules"
echo "  ⚠️  Monitor certificate expiry"
echo ""
