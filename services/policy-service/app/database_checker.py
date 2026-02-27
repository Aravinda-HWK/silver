#!/usr/bin/env python3
"""
Alternative check_user_exists implementation using shared database
This avoids the Thunder authentication issue by querying the database directly
"""

import sqlite3
import aiosqlite
from typing import Optional

async def check_user_exists_db(self, email: str) -> tuple[bool, Optional[str]]:
    """
    Check if user exists in shared SQLite database
    
    Args:
        email: Email address to validate
        
    Returns:
        Tuple of (exists: bool, error_message: Optional[str])
    """
    # Extract domain from email
    if '@' not in email:
        return False, None
    
    db_path = "/app/data/databases/shared.db"
    
    try:
        # Query shared database used by Raven
        async with aiosqlite.connect(db_path) as db:
            # Check users table
            cursor = await db.execute(
                "SELECT COUNT(*) FROM users WHERE email = ?",
                (email,)
            )
            row = await cursor.fetchone()
            count = row[0] if row else 0
            
            if count > 0:
                logger.info(f"User found in database: {email}")
                return True, None
            else:
                logger.info(f"User not found in database: {email}")
                return False, None
                
    except sqlite3.OperationalError as e:
        if "no such table" in str(e):
            logger.error(f"Database table not found: {e}")
            logger.error("The shared database may not be initialized yet")
            # Defer to avoid rejecting mail during initialization
            return False, "Database not ready"
        else:
            logger.error(f"Database error: {e}")
            return False, "Database error"
    except Exception as e:
        logger.error(f"Unexpected database error: {e}")
        return False, "Database error"


# Synchronous version (simpler, but blocks)
def check_user_exists_db_sync(email: str, db_path: str = "/app/data/databases/shared.db") -> tuple[bool, Optional[str]]:
    """
    Synchronous version - check if user exists in shared database
    
    Args:
        email: Email address to validate
        db_path: Path to SQLite database
        
    Returns:
        Tuple of (exists: bool, error_message: Optional[str])
    """
    if '@' not in email:
        return False, None
    
    try:
        conn = sqlite3.connect(db_path, timeout=5.0)
        cursor = conn.cursor()
        
        cursor.execute(
            "SELECT COUNT(*) FROM users WHERE email = ?",
            (email,)
        )
        count = cursor.fetchone()[0]
        conn.close()
        
        return (count > 0, None)
        
    except sqlite3.OperationalError as e:
        if "no such table" in str(e):
            return False, "Database not ready"
        else:
            return False, "Database error"
    except Exception as e:
        return False, "Database error"


# To use this, replace the check_user_exists method in main.py with:
# self.check_user_exists = check_user_exists_db.__get__(self, PostfixPolicyService)
