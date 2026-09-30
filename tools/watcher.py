#!/usr/bin/env python3
import os
import sys
import time
import json
import subprocess
import requests
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# Configuration
CHANNEL_ID = os.environ.get("DOCTRANSIT_CHANNEL_ID")
HOST_KEY = os.environ.get("DOCTRANSIT_HOST_KEY")
CLIENT_KEY = os.environ.get("DOCTRANSIT_CLIENT_KEY")
WORKER_URL = os.environ.get("DOCTRANSIT_WORKER_URL", "https://doctransit.in")
POLL_INTERVAL = 3
IDLE_THRESHOLD = 45

if not all([CHANNEL_ID, HOST_KEY, CLIENT_KEY]):
    print("Error: Missing required environment variables (DOCTRANSIT_CHANNEL_ID, DOCTRANSIT_HOST_KEY, DOCTRANSIT_CLIENT_KEY)")
    sys.exit(1)

def derive_key(client_key_hex):
    client_key = bytes.fromhex(client_key_hex)
    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=b"doctransit-v2",
        info=b"file-transfer",
    )
    return hkdf.derive(client_key)

def encrypt_payload(payload_str, aes_key):
    aesgcm = AESGCM(aes_key)
    iv = os.urandom(12)
    ciphertext = aesgcm.encrypt(iv, payload_str.encode('utf-8'), None)
    return iv + ciphertext

def get_git_info():
    try:
        status = subprocess.check_output(["git", "status", "--porcelain"], text=True).strip()
        if not status:
            return None, None
        
        diff = subprocess.check_output(["git", "diff", "HEAD"], text=True).strip()
        stat = subprocess.check_output(["git", "diff", "--stat", "HEAD"], text=True).strip()
        
        return stat, diff[:100000] # Truncate to ~100KB to stay within DO limits
    except subprocess.CalledProcessError:
        return None, None

def get_agent_summary():
    try:
        if os.path.exists(".agent-summary.md"):
            with open(".agent-summary.md", "r") as f:
                return f.read().strip()
    except Exception:
        pass
    return None

def main():
    print(f"Starting DocTransit Watcher for channel {CHANNEL_ID}...")
    aes_key = derive_key(CLIENT_KEY)
    
    last_change_time = 0
    last_state_hash = hash("")
    sent_state_hash = None
    
    while True:
        time.sleep(POLL_INTERVAL)
        
        stat, diff = get_git_info()
        summary = get_agent_summary()
        
        current_state = f"{stat}\n{diff}\n{summary}"
        current_hash = hash(current_state)
        
        if current_hash != last_state_hash:
            last_state_hash = current_hash
            last_change_time = time.time()
            continue
            
        if time.time() - last_change_time >= IDLE_THRESHOLD and current_hash != sent_state_hash and current_state.strip():
            print("Idle threshold reached. Pushing update...")
            
            payload = {
                "type": "watcher_update",
                "summary": summary,
                "stat": stat,
                "diff": diff
            }
            
            encrypted_data = encrypt_payload(json.dumps(payload), aes_key)
            
            try:
                res = requests.post(
                    f"{WORKER_URL}/c/{CHANNEL_ID}/notify?key={HOST_KEY}",
                    data=encrypted_data,
                    headers={"Content-Type": "application/octet-stream"},
                    timeout=10
                )
                if res.status_code == 200:
                    print("Update pushed successfully.")
                    sent_state_hash = current_hash
                else:
                    print(f"Failed to push update. Status: {res.status_code} - {res.text}")
            except Exception as e:
                print(f"Network error pushing update: {e}")

if __name__ == "__main__":
    main()
