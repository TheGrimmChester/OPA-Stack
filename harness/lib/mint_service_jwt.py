#!/usr/bin/env python3
"""Mint an HS256 service JWT matching Open-Auth-Go's ServiceClaims.

Claims mirror MintServiceJWTWithOrg: scope, optional org_id, iss, aud (array),
sub="service", iat/exp/nbf. Used to exercise OAM's resolve endpoints, which
accept a service token only (never a user token).
"""
import base64
import hashlib
import hmac
import json
import sys
import time


def b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def mint(secret: str, iss: str, aud: str, scope: str, org: str = "", ttl: int = 300) -> str:
    now = int(time.time())
    header = {"alg": "HS256", "typ": "JWT"}
    claims = {
        "scope": scope,
        "iss": iss,
        "aud": [aud],
        "sub": "service",
        "iat": now,
        "exp": now + ttl,
        "nbf": now - 30,
    }
    if org:
        claims["org_id"] = org
    signing_input = f"{b64(json.dumps(header).encode())}.{b64(json.dumps(claims).encode())}"
    sig = hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest()
    return f"{signing_input}.{b64(sig)}"


if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("usage: mint_jwt.py SECRET ISS AUD SCOPE [ORG]", file=sys.stderr)
        sys.exit(2)
    org = sys.argv[5] if len(sys.argv) > 5 else ""
    print(mint(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], org))
