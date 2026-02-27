#!/bin/bash
#
# Test script for Postfix Policy Service
# This script tests the policy service by sending sample requests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_HOST="${1:-localhost}"
POLICY_PORT="${2:-9000}"

echo "=================================="
echo "Postfix Policy Service Test"
echo "=================================="
echo "Host: $POLICY_HOST"
echo "Port: $POLICY_PORT"
echo ""

# Check if policy service is reachable
echo "1. Checking if policy service is reachable..."
if nc -z "$POLICY_HOST" "$POLICY_PORT" 2>/dev/null; then
    echo "✓ Policy service is reachable"
else
    echo "✗ Policy service is not reachable at $POLICY_HOST:$POLICY_PORT"
    echo "  Make sure the service is running:"
    echo "  docker ps | grep policy-service"
    exit 1
fi

echo ""
echo "2. Testing with sample recipient..."

# Send a test request using netcat
(
cat <<EOF
request=smtpd_access_policy
protocol_state=RCPT
protocol_name=ESMTP
client_address=192.168.1.100
client_name=mail.example.com
helo_name=mail.example.com
sender=test@example.com
recipient=testuser@example.com
recipient_count=0
queue_id=TEST123
instance=123.456.7
size=12345

EOF
) | nc "$POLICY_HOST" "$POLICY_PORT"

echo ""
echo "=================================="
echo "Test completed!"
echo ""
echo "To test specific recipients, use:"
echo "  python3 $SCRIPT_DIR/test_policy.py recipient@domain.com"
echo ""
echo "For interactive testing:"
echo "  python3 $SCRIPT_DIR/test_policy.py -i"
