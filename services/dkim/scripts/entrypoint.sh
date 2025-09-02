#!/bin/bash
set -e

# Load env variables from the .env file in the grandparent folder
if [ -f /etc/opendkim/../../.env ]; then
    echo "Loading environment variables from ../../.env"
    export $(grep -v '^#' /etc/opendkim/../../.env | xargs)
fi

# Defaults
MAIL_DOMAIN=${MAIL_DOMAIN:-example.org}
DKIM_SELECTOR=${DKIM_SELECTOR:-mail}
DKIM_KEY_SIZE=${DKIM_KEY_SIZE:-2048}

# Create directories
mkdir -p /etc/opendkim/keys/$MAIL_DOMAIN
chown -R opendkim:opendkim /etc/opendkim

# Generate DKIM keys if missing
if [ ! -f /etc/opendkim/keys/$MAIL_DOMAIN/$DKIM_SELECTOR.private ]; then
    echo "Generating DKIM keys for $MAIL_DOMAIN..."
    opendkim-genkey -b $DKIM_KEY_SIZE -s $DKIM_SELECTOR -d $MAIL_DOMAIN -D /etc/opendkim/keys/$MAIL_DOMAIN/
    chown -R opendkim:opendkim /etc/opendkim/keys
    chmod 600 /etc/opendkim/keys/$MAIL_DOMAIN/$DKIM_SELECTOR.private
    chmod 644 /etc/opendkim/keys/$MAIL_DOMAIN/$DKIM_SELECTOR.txt
    echo "DKIM keys ready."
fi

# Write TrustedHosts
cat > /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
192.168.65.0/16
172.16.0.0/12
10.0.0.0/8
*.${MAIL_DOMAIN}
EOF

# Write KeyTable
cat > /etc/opendkim/KeyTable <<EOF
$DKIM_SELECTOR._domainkey.$MAIL_DOMAIN $MAIL_DOMAIN:$DKIM_SELECTOR:/etc/opendkim/keys/$MAIL_DOMAIN/$DKIM_SELECTOR.private
EOF

# Write SigningTable
cat > /etc/opendkim/SigningTable <<EOF
*@$MAIL_DOMAIN $DKIM_SELECTOR._domainkey.$MAIL_DOMAIN
EOF

# Start OpenDKIM
echo "Starting OpenDKIM..."
echo ""
echo "========== DKIM DNS Record =========="
echo "Record name: $DKIM_SELECTOR._domainkey.$MAIL_DOMAIN"
echo "Record value:"
cat /etc/opendkim/keys/$MAIL_DOMAIN/$DKIM_SELECTOR.txt
echo "====================================="
echo ""

exec opendkim -f