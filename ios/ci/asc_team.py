#!/usr/bin/env python3
"""Asks App Store Connect which team owns Spade's bundle ID, and prints the team ID.

Used by testflight.sh. It also proves the API key works before the long build starts.

  python3 asc_team.py KEY.p8 BUNDLE_ID      (reads ASC_KEY_ID and ASC_ISSUER_ID)

Only the standard library and the openssl command are needed, so nothing is installed.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(sig: bytes) -> bytes:
    """openssl signs as DER (SEQUENCE of r and s); a JWT wants r and s as 32 bytes each."""
    if len(sig) < 8 or sig[0] != 0x30 or sig[2] != 0x02:
        raise ValueError("unexpected signature from openssl")
    rlen = sig[3]
    r = sig[4 : 4 + rlen]
    i = 4 + rlen
    if sig[i] != 0x02:
        raise ValueError("unexpected signature from openssl")
    s = sig[i + 2 : i + 2 + sig[i + 1]]
    return r.lstrip(b"\0").rjust(32, b"\0") + s.lstrip(b"\0").rjust(32, b"\0")


def token(key_path: str, key_id: str, issuer: str) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(claims).encode())}"
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(), capture_output=True, check=True,
    ).stdout
    return f"{signing_input}.{b64url(der_to_raw(der))}"


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    key_path, bundle_id = sys.argv[1], sys.argv[2]
    try:
        jwt = token(key_path, os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"])
    except (subprocess.CalledProcessError, ValueError):
        fail("ASC_KEY_P8 isn't a key openssl can read. Paste the whole .p8 file, "
             "including the BEGIN PRIVATE KEY and END PRIVATE KEY lines.")
    query = urllib.parse.urlencode({
        "filter[identifier]": bundle_id,
        "fields[bundleIds]": "identifier,seedId",
        "limit": "200",
    })
    request = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com/v1/bundleIds?{query}",
        headers={"Authorization": f"Bearer {jwt}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 401:
            fail("Apple didn't accept the API key. Check ASC_KEY_ID, ASC_ISSUER_ID and "
                 "ASC_KEY_P8 all come from the same key, and that the key hasn't been revoked.")
        if error.code == 403:
            fail("The API key isn't allowed to read App IDs. Make a key with Admin access.")
        fail(f"App Store Connect answered {error.code} when asked about {bundle_id}.")
    except urllib.error.URLError as error:
        fail(f"Couldn't reach App Store Connect: {error.reason}")
    for item in body.get("data", []):
        attributes = item.get("attributes", {})
        if attributes.get("identifier") == bundle_id and attributes.get("seedId"):
            print(attributes["seedId"])
            return
    fail(f"No App ID called {bundle_id} in this team. Register it first (ios/README.md, step 1).")


if __name__ == "__main__":
    main()
