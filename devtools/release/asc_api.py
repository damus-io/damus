#!/usr/bin/env python3
"""App Store Connect API client with no third-party dependencies.

Signs the ES256 JWT with `openssl dgst` and talks to the API over urllib, so it
runs on the stock macOS python3 without a pip install or a working Ruby. That
matters here: this is meant to be driven unattended over ssh, and the fewer
moving parts between "cut a build" and the HTTP request, the fewer ways it can
stop and wait for a human.

Credentials come from the environment:

  ASC_KEY_ID      the App Store Connect API key id (the KEY_ID in AuthKey_<KEY_ID>.p8)
  ASC_ISSUER_ID   the issuer id, shared by every key in the team
  ASC_KEY_PATH    path to the .p8 private key
                  (default: ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8,
                  which is also where xcodebuild and altool look)

Used as a library by the sibling release scripts. Also usable directly for
one-off queries:

  ./asc_api.py GET /v1/ciProducts
  ./asc_api.py POST /v1/ciBuildRuns '{"data": ...}'
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

AUDIENCE = "appstoreconnect-v1"
BASE_URL = "https://api.appstoreconnect.apple.com"
DEFAULT_KEY_DIR = os.path.expanduser("~/.appstoreconnect/private_keys")

# App Store Connect rejects tokens with a lifetime over 20 minutes.
TOKEN_TTL_SECONDS = 20 * 60


class AscError(Exception):
    pass


def _b64url(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _der_ecdsa_to_jose(der: bytes) -> bytes:
    """Convert openssl's DER SEQUENCE{INTEGER r, INTEGER s} to JOSE's r||s.

    openssl emits ECDSA signatures as DER; ES256 wants the two 32-byte integers
    concatenated. Getting this wrong yields a 401 that looks exactly like a bad
    key, so it is worth doing explicitly rather than by slicing.
    """
    if not der or der[0] != 0x30:
        raise AscError("openssl did not return a DER SEQUENCE")

    # Skip the SEQUENCE tag and its (possibly long-form) length.
    offset = 1
    if der[offset] & 0x80:
        offset += 1 + (der[offset] & 0x7F)
    else:
        offset += 1

    parts = []
    for _ in range(2):
        if der[offset] != 0x02:
            raise AscError("expected an INTEGER in the ECDSA signature")
        length = der[offset + 1]
        value = der[offset + 2 : offset + 2 + length]
        # DER integers are signed, so a leading zero byte may be padding.
        parts.append(value.lstrip(b"\x00").rjust(32, b"\x00"))
        offset += 2 + length

    return b"".join(parts)


def key_path() -> str:
    explicit = os.environ.get("ASC_KEY_PATH")
    if explicit:
        return os.path.expanduser(explicit)
    key_id = os.environ.get("ASC_KEY_ID")
    if not key_id:
        raise AscError("set ASC_KEY_ID (and ASC_ISSUER_ID) in the environment")
    return os.path.join(DEFAULT_KEY_DIR, f"AuthKey_{key_id}.p8")


def token() -> str:
    """Mint a short-lived bearer token for the configured API key."""
    key_id = os.environ.get("ASC_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer_id:
        raise AscError("set both ASC_KEY_ID and ASC_ISSUER_ID in the environment")

    path = key_path()
    if not os.path.isfile(path):
        raise AscError(f"no private key at {path}")

    issued_at = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": issued_at,
        "exp": issued_at + TOKEN_TTL_SECONDS,
        "aud": AUDIENCE,
    }
    signing_input = "{}.{}".format(
        _b64url(json.dumps(header, separators=(",", ":")).encode()),
        _b64url(json.dumps(payload, separators=(",", ":")).encode()),
    )

    signed = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", path],
        input=signing_input.encode(),
        capture_output=True,
    )
    if signed.returncode != 0:
        raise AscError(
            f"openssl could not sign with {path}: "
            f"{signed.stderr.decode(errors='replace').strip()}"
        )

    return f"{signing_input}.{_b64url(_der_ecdsa_to_jose(signed.stdout))}"


def request(method: str, path: str, body=None, bearer=None):
    """Make one API call. Returns (status, decoded body)."""
    bearer = bearer or token()
    req = urllib.request.Request(
        BASE_URL + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": f"Bearer {bearer}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as err:
        raw = err.read()
        try:
            return err.code, json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return err.code, {"raw": raw.decode(errors="replace")}


def get(path: str, bearer=None):
    """GET a path, raising on anything but success."""
    status, body = request("GET", path, bearer=bearer)
    if not 200 <= status < 300:
        raise AscError(f"GET {path} failed with HTTP {status}: {describe(body)}")
    return body


def describe(body) -> str:
    """Render an API error body as one readable line."""
    errors = body.get("errors") if isinstance(body, dict) else None
    if not errors:
        return json.dumps(body)[:800]
    return "; ".join(
        f"{e.get('code', '?')}: {e.get('detail') or e.get('title') or ''}".strip()
        for e in errors
    )


def main(argv) -> int:
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    if len(argv) == 2:
        method, path, body = "GET", argv[1], None
    else:
        method, path = argv[1].upper(), argv[2]
        body = json.loads(argv[3]) if len(argv) > 3 else None

    try:
        status, response = request(method, path, body)
    except AscError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    print(f"HTTP {status}")
    print(json.dumps(response, indent=2))
    return 0 if 200 <= status < 300 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
