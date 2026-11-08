#!/usr/bin/env python3
"""Validate provisioning and the private Keychain identity before release export."""
import datetime
import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile


def check(app: pathlib.Path, require_clients: bool = False,
          require_profile: bool = False) -> tuple[str, str] | None:
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if require_clients:
        google = info.get("ALTILLO_GOOGLE_MAIL_CLIENT_ID", "")
        microsoft = info.get("ALTILLO_MICROSOFT_MAIL_CLIENT_ID", "")
        if not re.fullmatch(r"[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com", google) or not re.fullmatch(
                r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", microsoft):
            raise ValueError("Publishing native mail requires registered Google and Microsoft client IDs.")
    configured = any(info.get(key, "").strip() for key in (
        "ALTILLO_GOOGLE_MAIL_CLIENT_ID", "ALTILLO_MICROSOFT_MAIL_CLIENT_ID"))
    profile_path = app / "Contents/embedded.provisionprofile"
    if not profile_path.exists():
        if require_profile:
            raise ValueError("Private Keychain access requires an embedded macOS provisioning profile.")
        if configured:
            raise ValueError("Native mail requires an embedded macOS provisioning profile.")
        return None
    profile = plistlib.loads(subprocess.check_output(
        ["security", "cms", "-D", "-i", str(profile_path)], stderr=subprocess.DEVNULL))
    signed = plistlib.loads(subprocess.check_output(
        ["codesign", "-d", "--entitlements", "-", "--xml", str(app)], stderr=subprocess.DEVNULL))
    if signed.get("com.apple.security.get-task-allow"):
        raise ValueError("A distributable mail build must not allow debugger attachment.")
    identifier = signed.get("com.apple.application-identifier", "")
    authorized = profile.get("Entitlements", {}).get("com.apple.application-identifier")
    if not identifier or identifier != authorized or not identifier.endswith("." + info["CFBundleIdentifier"]):
        raise ValueError("The signed application identifier must match this app's explicit profile.")
    if "$(" in identifier or "OSX" not in profile.get("Platform", []):
        raise ValueError("Native mail requires a resolved macOS application identifier.")
    if profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError("The mail signing profile has expired.")
    if not profile.get("ProvisionsAllDevices"):
        raise ValueError("A public release requires a Developer ID distribution profile.")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    signature = subprocess.run(["codesign", "-dv", str(app)], capture_output=True, text=True, check=True)
    team = re.search(r"^TeamIdentifier=(.+)$", signature.stderr, re.MULTILINE)
    if not team or team.group(1) not in profile.get("TeamIdentifier", []):
        raise ValueError("The signing team must match the embedded profile.")
    with tempfile.TemporaryDirectory(prefix="altillo-mail-certificate-") as directory:
        prefix = pathlib.Path(directory) / "certificate"
        subprocess.run(["codesign", "-d", "--extract-certificates=" + str(prefix), str(app)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if pathlib.Path(str(prefix) + "0").read_bytes() not in profile.get("DeveloperCertificates", []):
            raise ValueError("The signing certificate is not authorized by the embedded profile.")
    return info["CFBundleIdentifier"], profile["UUID"]


if __name__ == "__main__":
    try:
        result = check(pathlib.Path(sys.argv[1]),
                       require_clients="--require-clients" in sys.argv[2:],
                       require_profile="--require-profile" in sys.argv[2:])
        if result:
            # Only public signing metadata; never emit the complete profile.
            print("\t".join(result))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        sys.exit(f"Mail signing validation failed: {error}")
