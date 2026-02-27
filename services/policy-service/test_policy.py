#!/usr/bin/env python3
"""
Test script for Postfix Policy Service

This script simulates Postfix policy requests to test the policy service.
"""

import socket
import sys
import time
from typing import Dict, Optional


class PolicyTester:
    """Test client for Postfix policy service"""
    
    def __init__(self, host: str = "localhost", port: int = 9000):
        self.host = host
        self.port = port
    
    def send_request(self, attributes: Dict[str, str]) -> Optional[str]:
        """
        Send a policy request and return the response
        
        Args:
            attributes: Dictionary of policy attributes
            
        Returns:
            Response string or None on error
        """
        try:
            # Create socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(10)
            
            # Connect
            print(f"Connecting to {self.host}:{self.port}...")
            sock.connect((self.host, self.port))
            print("Connected!")
            
            # Build request
            request = ""
            for key, value in attributes.items():
                request += f"{key}={value}\n"
            request += "\n"  # Empty line terminates request
            
            print("\nSending request:")
            print(request)
            
            # Send request
            sock.sendall(request.encode('utf-8'))
            
            # Receive response
            response = b""
            while True:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                response += chunk
                if b"\n\n" in response:
                    break
            
            sock.close()
            
            response_str = response.decode('utf-8', errors='ignore')
            return response_str
            
        except socket.timeout:
            print("ERROR: Connection timed out")
            return None
        except ConnectionRefusedError:
            print("ERROR: Connection refused. Is the policy service running?")
            return None
        except Exception as e:
            print(f"ERROR: {e}")
            return None
    
    def test_recipient(self, recipient: str, sender: str = "test@example.com", 
                      client_address: str = "192.168.1.100") -> bool:
        """
        Test a recipient address
        
        Args:
            recipient: Recipient email to test
            sender: Sender email
            client_address: Client IP address
            
        Returns:
            True if accepted, False if rejected
        """
        print(f"\n{'='*60}")
        print(f"Testing recipient: {recipient}")
        print(f"{'='*60}")
        
        attributes = {
            "request": "smtpd_access_policy",
            "protocol_state": "RCPT",
            "protocol_name": "ESMTP",
            "client_address": client_address,
            "client_name": "mail.example.com",
            "helo_name": "mail.example.com",
            "sender": sender,
            "recipient": recipient,
            "recipient_count": "0",
            "queue_id": "TEST123",
            "instance": "123.456.7",
            "size": "12345",
        }
        
        response = self.send_request(attributes)
        
        if response is None:
            print("❌ No response received")
            return False
        
        print("\nResponse received:")
        print(response)
        
        # Parse response
        if "action=DUNNO" in response:
            print("✅ ACCEPTED - User exists or check passed")
            return True
        elif "action=REJECT" in response:
            print("❌ REJECTED - User not found")
            return False
        elif "action=DEFER" in response:
            print("⚠️  DEFERRED - Temporary error")
            return False
        else:
            print("❓ UNKNOWN RESPONSE")
            return False


def main():
    """Main entry point"""
    
    # Parse command line arguments
    if len(sys.argv) < 2:
        print("Usage: python test_policy.py <recipient_email> [host] [port]")
        print("\nExamples:")
        print("  python test_policy.py user@example.com")
        print("  python test_policy.py user@example.com localhost 9000")
        print("\nInteractive mode:")
        print("  python test_policy.py -i")
        sys.exit(1)
    
    # Check for interactive mode
    if sys.argv[1] == "-i":
        interactive_mode()
        return
    
    recipient = sys.argv[1]
    host = sys.argv[2] if len(sys.argv) > 2 else "localhost"
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 9000
    
    # Create tester
    tester = PolicyTester(host, port)
    
    # Test recipient
    result = tester.test_recipient(recipient)
    
    # Exit with appropriate code
    sys.exit(0 if result else 1)


def interactive_mode():
    """Interactive testing mode"""
    print("="*60)
    print("Postfix Policy Service - Interactive Test Mode")
    print("="*60)
    
    host = input("\nPolicy service host [localhost]: ").strip() or "localhost"
    port_str = input("Policy service port [9000]: ").strip() or "9000"
    port = int(port_str)
    
    tester = PolicyTester(host, port)
    
    print("\nEnter recipient emails to test (one per line)")
    print("Press Ctrl+C or enter 'quit' to exit")
    print()
    
    results = {"accepted": 0, "rejected": 0, "errors": 0}
    
    try:
        while True:
            recipient = input("Recipient email: ").strip()
            
            if not recipient or recipient.lower() == "quit":
                break
            
            result = tester.test_recipient(recipient)
            
            if result is None:
                results["errors"] += 1
            elif result:
                results["accepted"] += 1
            else:
                results["rejected"] += 1
            
            time.sleep(0.5)  # Small delay between requests
    
    except KeyboardInterrupt:
        print("\n\nExiting...")
    
    # Print summary
    print("\n" + "="*60)
    print("Test Summary")
    print("="*60)
    print(f"Accepted: {results['accepted']}")
    print(f"Rejected: {results['rejected']}")
    print(f"Errors:   {results['errors']}")
    print(f"Total:    {sum(results.values())}")


if __name__ == "__main__":
    main()
