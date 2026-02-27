#!/usr/bin/env python3
"""
Postfix Policy Service for Recipient Validation

This service integrates with Thunder IdP to validate recipients before accepting mail.
It listens on port 9000 and responds to Postfix policy delegation protocol requests.

Request Format from Postfix:
    request=smtpd_access_policy
    protocol_state=RCPT
    protocol_name=ESMTP
    client_address=1.2.3.4
    client_name=mail.example.com
    reverse_client_name=mail.example.com
    helo_name=mail.example.com
    sender=sender@example.com
    recipient=user@example.com
    recipient_count=0
    queue_id=8045F2AB23
    instance=123.456.7
    size=12345
    etrn_domain=
    stress=
    sasl_method=
    sasl_username=
    sasl_sender=
    ccert_subject=
    ccert_issuer=
    ccert_fingerprint=
    encryption_protocol=TLSv1.2
    encryption_cipher=ECDHE-RSA-AES256-GCM-SHA384
    encryption_keysize=256
    [empty line]

Response Format:
    action=DUNNO                    # Accept (user exists)
    action=REJECT User not found    # Reject with message
    action=DEFER_IF_PERMIT Try later # Temporary failure
"""

import asyncio
import logging
import os
import sys
from typing import Dict, Optional
import aiohttp
import yaml

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


class PostfixPolicyService:
    """Handles Postfix policy delegation protocol"""
    
    def __init__(self, idp_url: str, idp_token: Optional[str] = None):
        """
        Initialize the policy service
        
        Args:
            idp_url: Base URL of the Thunder IdP server
            idp_token: Optional authentication token for IdP API calls
        """
        self.idp_url = idp_url.rstrip('/')
        self.idp_token = idp_token
        self.session: Optional[aiohttp.ClientSession] = None
        
    async def start(self):
        """Initialize HTTP session"""
        self.session = aiohttp.ClientSession()
        logger.info("Policy service initialized")
        
    async def stop(self):
        """Cleanup HTTP session"""
        if self.session:
            await self.session.close()
        logger.info("Policy service stopped")
    
    def parse_request(self, data: str) -> Dict[str, str]:
        """
        Parse Postfix policy request
        
        Args:
            data: Raw request data from Postfix
            
        Returns:
            Dictionary of key-value pairs
        """
        attributes = {}
        for line in data.strip().split('\n'):
            line = line.strip()
            if not line or '=' not in line:
                continue
            key, value = line.split('=', 1)
            attributes[key] = value
        return attributes
    
    async def check_user_exists(self, email: str) -> tuple[bool, Optional[str]]:
        """
        Check if user exists in Thunder IdP
        
        Args:
            email: Email address to validate
            
        Returns:
            Tuple of (exists: bool, error_message: Optional[str])
        """
        if not self.session:
            return False, "Service not initialized"
        
        # Extract domain from email
        if '@' not in email:
            return False, "Invalid email format"
        
        local_part, domain = email.rsplit('@', 1)
        
        try:
            # Query Thunder SCIM API for user
            # Thunder uses SCIM 2.0 protocol: /scim2/Users
            url = f"{self.idp_url}/scim2/Users"
            params = {
                'filter': f'userName eq "{email}"'
            }
            
            headers = {}
            if self.idp_token:
                headers['Authorization'] = f'Bearer {self.idp_token}'
            
            logger.debug(f"Checking user existence: {email}")
            
            async with self.session.get(
                url,
                params=params,
                headers=headers,
                timeout=aiohttp.ClientTimeout(total=5),
                ssl=False  # For local development; use True in production with valid certs
            ) as response:
                if response.status == 200:
                    data = await response.json()
                    total_results = data.get('totalResults', 0)
                    
                    if total_results > 0:
                        logger.info(f"User found: {email}")
                        return True, None
                    else:
                        logger.info(f"User not found: {email}")
                        return False, None
                elif response.status == 401:
                    logger.error("IdP authentication failed")
                    return False, "IdP authentication error"
                else:
                    logger.error(f"IdP returned status {response.status}")
                    return False, "IdP query failed"
                    
        except asyncio.TimeoutError:
            logger.error(f"Timeout checking user: {email}")
            return False, "Timeout"
        except aiohttp.ClientError as e:
            logger.error(f"Network error checking user {email}: {e}")
            return False, "Network error"
        except Exception as e:
            logger.error(f"Unexpected error checking user {email}: {e}")
            return False, "Internal error"
    
    async def process_request(self, request: Dict[str, str]) -> str:
        """
        Process a policy request and generate response
        
        Args:
            request: Parsed request attributes
            
        Returns:
            Policy response string
        """
        # Log the request
        logger.info(f"Processing request: protocol_state={request.get('protocol_state')}, "
                   f"recipient={request.get('recipient')}, "
                   f"client={request.get('client_address')}")
        
        # Only check RCPT requests
        if request.get('request') != 'smtpd_access_policy':
            logger.warning(f"Unknown request type: {request.get('request')}")
            return "action=DUNNO\n\n"
        
        protocol_state = request.get('protocol_state', '')
        if protocol_state != 'RCPT':
            # Not a recipient check, allow other checks to proceed
            return "action=DUNNO\n\n"
        
        recipient = request.get('recipient', '')
        if not recipient:
            logger.warning("No recipient in request")
            return "action=DUNNO\n\n"
        
        # Check if user exists in IdP
        exists, error = await self.check_user_exists(recipient)
        
        if error:
            # Temporary error - tell Postfix to try again later
            if error in ["Timeout", "Network error", "IdP query failed"]:
                logger.warning(f"Temporary failure for {recipient}: {error}")
                return "action=DEFER_IF_PERMIT Service temporarily unavailable\n\n"
            else:
                # Permanent error - accept for now to avoid blocking mail
                logger.error(f"Policy service error for {recipient}: {error}")
                return "action=DUNNO\n\n"
        
        if exists:
            # User exists - accept
            logger.info(f"ACCEPT: {recipient}")
            return "action=DUNNO\n\n"
        else:
            # User does not exist - reject
            logger.info(f"REJECT: {recipient}")
            return f"action=REJECT 5.1.1 <{recipient}>: Recipient address rejected: User unknown in virtual mailbox table\n\n"
    
    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """
        Handle a single client connection
        
        Args:
            reader: Stream reader for incoming data
            writer: Stream writer for outgoing data
        """
        addr = writer.get_extra_info('peername')
        logger.debug(f"Connection from {addr}")
        
        try:
            # Read request until empty line
            data = b''
            while True:
                line = await reader.readline()
                data += line
                if line == b'\n' or not line:
                    break
            
            if not data:
                logger.warning(f"Empty request from {addr}")
                writer.close()
                await writer.wait_closed()
                return
            
            # Parse and process request
            request_str = data.decode('utf-8', errors='ignore')
            request = self.parse_request(request_str)
            
            # Generate response
            response = await self.process_request(request)
            
            # Send response
            writer.write(response.encode('utf-8'))
            await writer.drain()
            
        except Exception as e:
            logger.error(f"Error handling client {addr}: {e}", exc_info=True)
            # Send error response
            try:
                writer.write(b"action=DEFER_IF_PERMIT Service error\n\n")
                await writer.drain()
            except:
                pass
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except:
                pass
            logger.debug(f"Connection closed from {addr}")


async def main():
    """Main entry point"""
    
    # Load configuration
    config_file = os.getenv('CONFIG_FILE', '/etc/postfix/silver.yaml')
    idp_url = os.getenv('IDP_URL', 'https://thunder-server:8090')
    idp_token = os.getenv('IDP_TOKEN', None)
    host = os.getenv('POLICY_HOST', '0.0.0.0')
    port = int(os.getenv('POLICY_PORT', '9000'))
    
    # Try to load IdP configuration from silver.yaml if it exists
    if os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
                # You can add IdP configuration to silver.yaml in the future
                logger.info(f"Loaded configuration from {config_file}")
        except Exception as e:
            logger.warning(f"Could not load config file: {e}")
    
    logger.info(f"Starting Postfix Policy Service")
    logger.info(f"IdP URL: {idp_url}")
    logger.info(f"Listening on {host}:{port}")
    
    # Initialize policy service
    policy_service = PostfixPolicyService(idp_url, idp_token)
    await policy_service.start()
    
    # Start server
    server = await asyncio.start_server(
        policy_service.handle_client,
        host,
        port
    )
    
    addr = server.sockets[0].getsockname()
    logger.info(f"Policy service running on {addr}")
    
    try:
        async with server:
            await server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        await policy_service.stop()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Interrupted")
        sys.exit(0)
