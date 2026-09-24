#!/usr/bin/env python3
"""Creates (or re-creates) Altillo's Developer ID provisioning profile with iCloud, via the App Store Connect API.

Only the release build needs it: it lets the notarized app write the legacy `openusage.mobile.v1` file into the
existing iCloud container `iCloud.me.badia.ailimits`, so the old TestFlight iPhone app keeps getting data
(docs/uso-ia.md, docs/release.md "iCloud (transición)").

What it does, idempotently:
  1. finds or creates the bundle ID `me.badia.altillo` ("Altillo", macOS);
  2. makes sure the ICLOUD capability is on (iCloud Documents / "Xcode 6+" style);
  3. finds the Developer ID Application certificate that matches the identity in the login keychain;
  4. deletes any older profile with the same name and creates a MAC_APP_DIRECT profile for that pair;
  5. downloads it to Config/Provisioning/ (gitignored), checks it really allows the container, and records its
     path in Config/Local.xcconfig as ALTILLO_ICLOUD_PROFILE.

It never creates an iCloud container (containers can't be deleted). The App Store Connect API can't assign a
container to an App ID either, so that one step is manual; if the new profile doesn't list the container this
script deletes it again and prints the exact clicks.

Credentials: ASC_ISSUER, ASC_KEY_ID and ASC_P8 (path to the .p8) from the environment, or from the file given
with --env-file (default ~/.config/aurio/asc/env when it exists). They are never printed. Needs only python3
and openssl (both ship with macOS).

Usage: script/icloud-profile.py [--env-file PATH] [--no-xcconfig]
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "me.badia.altillo"
BUNDLE_NAME = "Altillo"
TEAM_ID = "9L2TD7KVV9"
CONTAINER = "iCloud.me.badia.ailimits"
PROFILE_NAME = "Altillo Developer ID iCloud"
PROFILE_REL_PATH = "Config/Provisioning/Altillo_DeveloperID_iCloud.provisionprofile"
XCCONFIG_KEY = "ALTILLO_ICLOUD_PROFILE"

MANUAL_STEPS = f"""
The App Store Connect API can't assign an iCloud container to an App ID; do this once by hand:

  1. Open https://developer.apple.com/account/resources/identifiers/list and click "{BUNDLE_ID}" ({BUNDLE_NAME}).
  2. In Capabilities, iCloud is already ticked: click "Edit" (or "Configure") next to it.
  3. Tick ONLY the existing container "{CONTAINER}" and click Continue / Save.
     Do NOT click "+" to create a new container (containers can never be deleted).
  4. Confirm the "modify App ID capabilities" dialog (it invalidates older profiles, which is expected).
  5. Run this script again: script/icloud-profile.py
"""


# ---- App Store Connect API ------------------------------------------------------------------------------

def load_credentials(env_file: str | None) -> dict[str, str]:
    creds = {k: os.environ[k] for k in ("ASC_ISSUER", "ASC_KEY_ID", "ASC_P8") if os.environ.get(k)}
    path = env_file or os.path.expanduser("~/.config/aurio/asc/env")
    if len(creds) < 3 and os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip().removeprefix("export ").strip()
            if key in ("ASC_ISSUER", "ASC_KEY_ID", "ASC_P8") and key not in creds:
                creds[key] = os.path.expanduser(os.path.expandvars(value.strip().strip('"').strip("'")))
    missing = [k for k in ("ASC_ISSUER", "ASC_KEY_ID", "ASC_P8") if not creds.get(k)]
    if missing:
        sys.exit(f"Missing App Store Connect API credentials: {', '.join(missing)} (env or --env-file).")
    if not os.path.isfile(creds["ASC_P8"]):
        sys.exit("ASC_P8 does not point to a readable .p8 file.")
    return creds


def _b64url(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def _der_to_raw(signature: bytes) -> bytes:
    """ECDSA DER (SEQUENCE { INTEGER r, INTEGER s }) -> JWS raw r||s (32 bytes each)."""
    def read_len(buf: bytes, i: int) -> tuple[int, int]:
        n = buf[i]
        if n < 0x80:
            return n, i + 1
        count = n & 0x7F
        return int.from_bytes(buf[i + 1:i + 1 + count], "big"), i + 1 + count

    assert signature[0] == 0x30, "not a DER sequence"
    _, i = read_len(signature, 1)
    parts = []
    for _ in range(2):
        assert signature[i] == 0x02, "not a DER integer"
        length, i = read_len(signature, i + 1)
        parts.append(int.from_bytes(signature[i:i + length], "big"))
        i += length
    return b"".join(p.to_bytes(32, "big") for p in parts)


def make_token(creds: dict[str, str]) -> str:
    header = {"alg": "ES256", "kid": creds["ASC_KEY_ID"], "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": creds["ASC_ISSUER"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing_input = _b64url(json.dumps(header).encode()) + b"." + _b64url(json.dumps(payload).encode())
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", creds["ASC_P8"]], input=signing_input,
                         capture_output=True, check=True).stdout
    return (signing_input + b"." + _b64url(_der_to_raw(der))).decode()


class ASC:
    def __init__(self, creds: dict[str, str]):
        self.creds = creds

    def __call__(self, method: str, path: str, body: dict | None = None) -> tuple[int, dict | None]:
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(API + path, data=data, method=method)
        request.add_header("Authorization", "Bearer " + make_token(self.creds))
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return response.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                return error.code, json.loads(raw)
            except ValueError:
                return error.code, {"errors": [{"detail": raw.decode(errors="replace")[:500]}]}

    def must(self, method: str, path: str, body: dict | None = None, ok=(200, 201, 204)) -> dict | None:
        status, out = self(method, path, body)
        if status not in ok:
            details = "; ".join(e.get("detail") or e.get("title", "") for e in (out or {}).get("errors", []))
            if status in (401, 403):
                sys.exit(f"{method} {path} was refused ({status}): {details}\n"
                         "The API key needs the Admin or App Manager role with access to Certificates, "
                         "Identifiers & Profiles. Otherwise do the steps in docs/release.md by hand.")
            sys.exit(f"{method} {path} failed ({status}): {details}")
        return out


# ---- steps --------------------------------------------------------------------------------------------------

def ensure_bundle_id(api: ASC) -> str:
    out = api.must("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE_ID}&limit=200")
    for item in out["data"]:
        if item["attributes"]["identifier"] == BUNDLE_ID:
            print(f"    bundle ID {BUNDLE_ID}: {item['id']} (exists)")
            return item["id"]
    out = api.must("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": BUNDLE_ID, "name": BUNDLE_NAME, "platform": "MAC_OS"}}})
    print(f"    bundle ID {BUNDLE_ID}: {out['data']['id']} (created)")
    return out["data"]["id"]


def ensure_icloud(api: ASC, bundle_id: str) -> None:
    out = api.must("GET", f"/v1/bundleIds/{bundle_id}/bundleIdCapabilities")
    if any(c["attributes"]["capabilityType"] == "ICLOUD" for c in out["data"]):
        print("    iCloud capability: on (exists)")
        return
    api.must("POST", "/v1/bundleIdCapabilities", {"data": {
        "type": "bundleIdCapabilities",
        "attributes": {"capabilityType": "ICLOUD",
                       "settings": [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}]},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}}}})
    print("    iCloud capability: on (enabled now)")


def keychain_developer_id_sha1() -> str:
    listing = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                             capture_output=True, text=True).stdout
    for line in listing.splitlines():
        match = re.search(r"\)\s+([0-9A-F]{40})\s+\"Developer ID Application: .*\(" + TEAM_ID + r"\)\"", line)
        if match:
            return match.group(1)
    sys.exit(f"No 'Developer ID Application ({TEAM_ID})' identity in the keychain.")


def find_certificate(api: ASC, sha1: str) -> str:
    out = api.must("GET", "/v1/certificates?filter[certificateType]=DEVELOPER_ID_APPLICATION&limit=200")
    for item in out["data"]:
        content = item["attributes"].get("certificateContent")
        if content and hashlib.sha1(base64.b64decode(content)).hexdigest().upper() == sha1:
            print(f"    Developer ID certificate: {item['id']} (SHA-1 {sha1[:8]}…)")
            return item["id"]
    sys.exit(f"No Developer ID Application certificate in the account matches keychain SHA-1 {sha1}.")


def recreate_profile(api: ASC, bundle_id: str, cert_id: str) -> tuple[str, bytes]:
    out = api.must("GET", f"/v1/profiles?filter[name]={urllib.request.quote(PROFILE_NAME)}&limit=200")
    for item in out["data"]:
        if item["attributes"]["name"] == PROFILE_NAME:
            api.must("DELETE", f"/v1/profiles/{item['id']}")
            print(f"    deleted older profile {item['id']}")
    out = api.must("POST", "/v1/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": PROFILE_NAME, "profileType": "MAC_APP_DIRECT"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
            "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})
    profile_id = out["data"]["id"]
    print(f"    profile \"{PROFILE_NAME}\": {profile_id} (created)")
    return profile_id, base64.b64decode(out["data"]["attributes"]["profileContent"])


def decode_profile(data: bytes) -> dict:
    with tempfile.NamedTemporaryFile(suffix=".provisionprofile") as handle:
        handle.write(data)
        handle.flush()
        plist = subprocess.run(["security", "cms", "-D", "-i", handle.name], capture_output=True, check=True).stdout
    return plistlib.loads(plist)


def record_in_xcconfig(rel_path: str) -> None:
    path = os.path.join(ROOT, "Config", "Local.xcconfig")
    if not os.path.exists(path):
        print(f"    Config/Local.xcconfig not found; add: {XCCONFIG_KEY} = {rel_path}")
        return
    text = open(path, encoding="utf-8").read()
    line = f"{XCCONFIG_KEY} = {rel_path}"
    if re.search(rf"^{XCCONFIG_KEY}\s*=.*$", text, flags=re.M):
        text = re.sub(rf"^{XCCONFIG_KEY}\s*=.*$", line, text, flags=re.M)
    else:
        text = text.rstrip("\n") + (
            "\n\n// Developer ID profile with iCloud (iCloud.me.badia.ailimits) for release builds only; created by\n"
            "// script/icloud-profile.py. See docs/release.md.\n" + line + "\n")
    open(path, "w", encoding="utf-8").write(text)
    print(f"    Config/Local.xcconfig: {line}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--env-file")
    parser.add_argument("--no-xcconfig", action="store_true", help="don't touch Config/Local.xcconfig")
    args = parser.parse_args()

    api = ASC(load_credentials(args.env_file))
    print("==> App Store Connect")
    bundle_id = ensure_bundle_id(api)
    ensure_icloud(api, bundle_id)
    cert_id = find_certificate(api, keychain_developer_id_sha1())
    profile_id, content = recreate_profile(api, bundle_id, cert_id)

    info = decode_profile(content)
    entitlements = info.get("Entitlements", {})
    containers = entitlements.get("com.apple.developer.icloud-container-identifiers", [])
    if CONTAINER not in containers:
        api.must("DELETE", f"/v1/profiles/{profile_id}")
        print(f"    deleted profile {profile_id} again: it doesn't allow {CONTAINER} "
              f"(App ID containers: {containers or 'none'})")
        print(MANUAL_STEPS)
        sys.exit(2)

    out_path = os.path.join(ROOT, PROFILE_REL_PATH)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as handle:
        handle.write(content)
    print(f"==> saved {PROFILE_REL_PATH} (UUID {info.get('UUID')}, expires {info.get('ExpirationDate')})")
    print(f"    application-identifier: {entitlements.get('com.apple.application-identifier')}")
    print(f"    iCloud containers: {', '.join(containers)}")
    if not args.no_xcconfig:
        record_in_xcconfig(PROFILE_REL_PATH)


if __name__ == "__main__":
    main()
