#!/bin/bash

# ============================================
#  Silver Mail Setup Wizard
# ============================================

# Colors
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Get the script directory (where init.sh is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Services directory contains docker-compose.yaml
SERVICES_DIR="$(cd "${SCRIPT_DIR}/../../services" && pwd)"
# Conf directory contains config files
CONF_DIR="$(cd "${SCRIPT_DIR}/../../conf" && pwd)"
CONFIG_FILE="${CONF_DIR}/silver.yaml"

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
echo -e " 🚀 ${GREEN}Welcome to Silver Mail System Setup${NC}"
echo "---------------------------------------------"

MAIL_DOMAIN=""

# ================================
# Step 1: Domain Configuration
# ================================
echo -e "\n${YELLOW}Step 1/8: Configure domain name${NC}"

MAIL_DOMAIN=$(grep -m 1 '^domain:' "$CONFIG_FILE" | sed 's/domain: //' | xargs)

# Validate if MAIL_DOMAIN is empty
if [ -z "$MAIL_DOMAIN" ]; then
	echo -e "${RED}Error: Domain name is not configured or is empty. Please set it in '$CONFIG_FILE'.${NC}"
	exit 1 # Exit the script with a failure status
else
	echo "Domain name found: $MAIL_DOMAIN"
	# ...continue with the rest of your script...
fi

if ! [[ "$MAIL_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
	echo -e "${RED}✗ Warning: '${MAIL_DOMAIN}' does not look like a valid domain name.${NC}"
	exit 1
fi

# ================================
# Step 5: Ensure ${MAIL_DOMAIN} points to 127.0.0.1 in /etc/hosts
# ================================
echo -e "\n${YELLOW}Step 5/8: Updating ${MAIL_DOMAIN} mapping in /etc/hosts${NC}"

if grep -q "[[:space:]]${MAIL_DOMAIN}" /etc/hosts; then
	# Replace existing entry
	sudo sed -i "/^[^#]*[[:space:]]${MAIL_DOMAIN}\([[:space:]]\|$\)/s/^.*[[:space:]]${MAIL_DOMAIN}\([[:space:]]\|$\).*/127.0.0.1   ${MAIL_DOMAIN}/" /etc/hosts
	echo -e "${GREEN}✓ Updated existing ${MAIL_DOMAIN} entry to 127.0.0.1${NC}"
else
	# Add new if not present
	echo "127.0.0.1   ${MAIL_DOMAIN}" | sudo tee -a /etc/hosts >/dev/null
	echo -e "${GREEN}✓ Added ${MAIL_DOMAIN} entry to /etc/hosts${NC}"
fi

# ================================
# Step 7: Docker Setup
# ================================
echo -e "\n${YELLOW}Step 7/8: Starting Docker services${NC}"

(cd "${SERVICES_DIR}" && docker compose up -d )
if [ $? -ne 0 ]; then
	echo -e "${RED}✗ Docker compose failed. Please check the logs.${NC}"
	exit 1
fi

# ================================
# Step 8: Initialize Thunder User Schema
# ================================

THUNDER_HOST=${MAIL_DOMAIN}
THUNDER_PORT=8090

echo -e "\n${YELLOW}Step 8/8: Creating default user schema in Thunder${NC}"

SCHEMA_RESPONSE=$(curl -w "\n%{http_code}" -X POST \
	-H "Content-Type: application/json" \
	-H "Accept: application/json" \
	https://${THUNDER_HOST}:${THUNDER_PORT}/user-schemas \
	-d "{
    \"name\": \"emailuser\",
    \"schema\": {
      \"username\": { \"type\": \"string\", \"unique\": true },
      \"password\": { \"type\": \"string\" },
      \"email\": { \"type\": \"string\", \"unique\": true }
    }
  }")

SCHEMA_BODY=$(echo "$SCHEMA_RESPONSE" | head -n -1)
SCHEMA_STATUS=$(echo "$SCHEMA_RESPONSE" | tail -n1)

if [ "$SCHEMA_STATUS" -eq 201 ] || [ "$SCHEMA_STATUS" -eq 200 ]; then
	echo -e "${GREEN}✓ User schema 'emailuser' created successfully (HTTP $SCHEMA_STATUS)${NC}"
else
	echo -e "${RED}✗ Failed to create user schema (HTTP $SCHEMA_STATUS)${NC}"
	echo "Response: $SCHEMA_BODY"
	exit 1
fi

# ================================
# Public DKIM Key Instructions
# ================================
chmod +x "${SCRIPT_DIR}/../utils/get-dkim.sh"
(cd "${SCRIPT_DIR}/../utils" && ./get-dkim.sh)
