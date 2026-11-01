#!/usr/bin/env python3
"""Run a synthetic Keychain transaction under the exported app's exact signing authorization."""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile


def check(app: pathlib.Path, identity: str) -> None:
    source = pathlib.Path(__file__).with_name("mail-keychain-smoke.swift")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    profile = app / "Contents/embedded.provisionprofile"
    if not profile.is_file():
        raise ValueError("A provisioned app is required for the real Keychain check.")
    entitlements = subprocess.check_output(
        ["codesign", "-d", "--entitlements", "-", "--xml", str(app)], stderr=subprocess.DEVNULL)
    parsed = plistlib.loads(entitlements)
    if not parsed.get("com.apple.application-identifier") or parsed.get("com.apple.security.get-task-allow"):
        raise ValueError("Use the provisioned distribution entitlements for this check.")
    with tempfile.TemporaryDirectory(prefix="altillo-keychain-smoke-") as directory:
        root = pathlib.Path(directory)
        helper = root / "NativeMailKeychainQA.app"
        binary = helper / "Contents/MacOS/NativeMailKeychainQA"
        binary.parent.mkdir(parents=True)
        (helper / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": info["CFBundleIdentifier"], "CFBundleExecutable": binary.name,
            "CFBundleName": "NativeMailKeychainQA", "CFBundlePackageType": "APPL", "LSUIElement": True
        }))
        shutil.copyfile(profile, helper / "Contents/embedded.provisionprofile")
        entitlement_path = root / "entitlements.plist"
        entitlement_path.write_bytes(entitlements)
        subprocess.run(["swiftc", str(source), "-o", str(binary)], check=True, timeout=120)
        # The helper is local and disposable. No timestamp service, notarization or UI is involved.
        subprocess.run(["codesign", "--force", "--sign", identity, "--entitlements", str(entitlement_path),
                        "--options", "runtime", "--timestamp=none", str(helper)], check=True, timeout=60)
        subprocess.run(["codesign", "--verify", "--strict", str(helper)], check=True)
        subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    try:
        check(pathlib.Path(sys.argv[1]), sys.argv[2])
    except (ValueError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        sys.exit(f"Native mail Keychain check failed: {error}")
