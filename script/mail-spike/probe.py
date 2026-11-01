#!/usr/bin/env python3
"""R01 local experiment. No external dependencies, sending mail, or reading mailbox databases."""
import argparse
from email.message import EmailMessage
from email.utils import formatdate
import hashlib
import json
import os
import plistlib
from pathlib import Path
import select
import socket
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path.home() / "Library/Developer/BuildCache/altillo-mail-spike"
SOCKET = CACHE / "mail.sock"
APP = CACHE / "AltilloMailSpike.app"
HELPER = APP / "Contents/MacOS/altillo-mail-spike"
MANIFEST = CACHE / "installation.json"
RULE_NAME = "Altillo R01 Spike (test only)"
SCRIPT = Path.home() / "Library/Application Scripts/com.apple.mail/Altillo-R01-Spike.scpt"
BRIDGE_SCRIPT = SCRIPT.parent / "Altillo-R01-Bridge.scpt"


def apple_string(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'


def applescript(source, timeout=12):
    result = subprocess.run(["/usr/bin/osascript", "-"], input=source, text=True,
                            capture_output=True, timeout=timeout)
    if result.returncode:
        # Never print arbitrary Apple Event error descriptions: a message can be embedded in them.
        raise RuntimeError("AppleScript failed; no mail content logged")
    return result.stdout.strip()


def render_script(destination, socket_path=SOCKET, prefix="ALTILLO-MAIL-SPIKE "):
    bridge = destination.parent / "Altillo-R01-Bridge.scpt"
    with tempfile.TemporaryDirectory(prefix="altillo-mail-compile-") as work:
        for name, target in [("Bridge", bridge), ("MailRule", destination)]:
            template = (ROOT / f"script/mail-spike/{name}.applescript").read_text()
            for key, value in [("__HELPER_PATH__", HELPER), ("__SOCKET_PATH__", socket_path),
                               ("__TRACE_PATH__", CACHE / "trace.txt"), ("__BRIDGE_PATH__", bridge),
                               ("ALTILLO-MAIL-SPIKE ", prefix)]:
                template = template.replace(apple_string(key), apple_string(value))
            source = Path(work) / f"{name}.applescript"
            source.write_text(template)
            subprocess.run(["/usr/bin/osacompile", "-o", str(target), str(source)], check=True, capture_output=True)


def build():
    CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = CACHE.lstat()
    if CACHE.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError("Build directory must be private and owned by the current user")
    HELPER.parent.mkdir(parents=True, exist_ok=True)
    (APP / "Contents/Info.plist").write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier="me.badia.altillo.mail-spike", CFBundleName="Altillo Mail Spike",
        CFBundleExecutable=HELPER.name, CFBundlePackageType="APPL", LSUIElement=True)))
    subprocess.run(["/usr/bin/swiftc", "-swift-version", "6", "-parse-as-library",
                    str(ROOT / "script/mail-spike/Main.swift"),
                    str(ROOT / "Packages/AltilloKit/Sources/AltilloAgents/UnixSocket.swift"),
                    "-o", str(HELPER)], check=True)
    render_script(CACHE / "Fixture.scpt")
    print("Built native helper and compiled Mail rule")


def fixture(**overrides):
    event = dict(version=1, messageID="fixture@example.invalid", sender="Synthetic café 日本語",
                 subject="ALTILLO-MAIL-SPIKE Access", body="Your verification code is 482913\n"
                 "https://example.invalid/login?token=synthetic", receivedAt=time.time())
    event.update(overrides)
    return json.dumps(event, ensure_ascii=False).encode()


def send(path, payload, success=True):
    result = subprocess.run([str(HELPER), "send", "--socket", str(path)], input=payload,
                            capture_output=True, timeout=4)
    assert (result.returncode == 0) == success, "Unexpected delivery status"
    # Logs must never contain content, even for malformed input.
    assert b"482913" not in result.stdout + result.stderr
    assert b"synthetic" not in result.stdout + result.stderr
    return result.stdout.strip()


def test():
    subprocess.run([str(HELPER), "self-test"], check=True, timeout=5)
    with tempfile.TemporaryDirectory(prefix="altillo-mail-test-", dir="/tmp") as work:
        path = Path(work) / "mail.sock"
        # TemporaryDirectory is private and short enough for AF_UNIX on Darwin.
        listener = subprocess.Popen([str(HELPER), "listen", "--socket", str(path), "--duration", "8", "--headless"],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            assert select.select([listener.stdout], [], [], 3)[0], "Listener failed to start"
            assert listener.stdout.readline().strip() == b"listening"
            assert (path.stat().st_mode & 0o777) == 0o600
            assert send(path, fixture()) == b"accepted"
            assert send(path, fixture()) == b"duplicate"
            send(path, fixture(messageID="stale@example.invalid", receivedAt=time.time() - 301), False)
            send(path, fixture(messageID="future@example.invalid", receivedAt=time.time() + 60), False)
            send(path, fixture(messageID="ordinary@example.invalid", subject="Ordinary mail"), False)
            send(path, b"not JSON", False)
            send(path, fixture(body="x" * 70_000), False)
            # A connected peer that sends nothing is closed within the server deadline.
            with socket.socket(socket.AF_UNIX) as stalled_client:
                stalled_client.connect(str(path))
                stalled_client.settimeout(2)
                assert stalled_client.recv(100).strip() == b"rejected"
            # A wedged receiver cannot hold the Mail helper indefinitely.
            with socket.socket(socket.AF_UNIX) as stalled_server:
                stalled_path = Path(work) / "stalled.sock"
                stalled_server.bind(str(stalled_path))
                stalled_server.listen(1)
                started = time.monotonic()
                send(stalled_path, fixture(), False)
                assert time.monotonic() - started < 2
            # Execute the real AppleScriptObjC serializer/NSTask/stdin bridge with a synthetic fixture.
            script = Path(work) / "Fixture.scpt"
            render_script(script, path)
            result = subprocess.run(["/usr/bin/osascript", str(script), "objc@example.invalid"],
                                    capture_output=True, timeout=5)
            assert result.returncode == 0 and result.stdout.strip() == b"true", (
                "Synthetic AppleScriptObjC bridge failed: " + repr((result.returncode, result.stdout, result.stderr)))
            # A listener that's already live cannot be replaced by a second experiment.
            second = subprocess.run([str(HELPER), "listen", "--socket", str(path), "--headless", "--duration", "1"],
                                    capture_output=True, timeout=3)
            assert second.returncode != 0 and path.exists()
            output, error = listener.communicate(timeout=10)
            assert listener.returncode == 0 and not path.exists(), "Listener did not clean up its socket"
            assert output.count(b"received code=true link=true") == 2, "Expected two unique accepted messages"
            assert b"482913" not in output + error and b"synthetic" not in output + error
            started = time.monotonic()
            send(path, fixture(), False)
            assert time.monotonic() - started < 2
            missing = subprocess.run(["/usr/bin/osascript", str(script)], capture_output=True, timeout=5)
            assert missing.stdout.strip() == b"false"
            print("Transport passed: delivery, deduplication, expiry, malformed/oversize input, AppleScriptObjC, permissions, cleanup, unavailable receiver")
        finally:
            if listener.poll() is None:
                listener.terminate()
                listener.communicate(timeout=3)


def prepare():
    if MANIFEST.exists() or SCRIPT.exists() or BRIDGE_SCRIPT.exists() or SCRIPT.is_symlink() or BRIDGE_SCRIPT.is_symlink():
        raise RuntimeError("An installation or same-name script already exists; inspect status first")
    if applescript('application id "com.apple.mail" is running') != "true":
        raise RuntimeError("Open Apple Mail before installing the test rule")
    SCRIPT.parent.mkdir(parents=True, exist_ok=True)
    prefix = "ALTILLO-MAIL-SPIKE " + uuid.uuid4().hex[:12]
    manifest = dict(rule=RULE_NAME, script=str(SCRIPT), prefix=prefix)
    if not HELPER.exists():
        raise RuntimeError("Build the native helper first")
    # Do not assign Mail's `run script` property: macOS 27 duplicated the absolute path.
    # Rule creation and script selection are explicit in Mail's own editor.
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    try:
        render_script(SCRIPT, prefix=prefix)
        manifest["scripts"] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [SCRIPT, BRIDGE_SCRIPT]}
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
        print("Prepared test scripts. No Mail rule has been installed or enabled.")
        print("In Mail Settings > Rules create:", RULE_NAME)
        print("Subject contains the test subject; action Run AppleScript > Altillo-R01-Spike.")
        print("Choose Don't Apply when asked about previous messages.")
        print("Test subject:", prefix)
    except Exception:
        manifest["scripts"] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in [SCRIPT, BRIDGE_SCRIPT] if p.exists()}
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
        print("Installation incomplete; run status/remove to inspect and clean owned artifacts.")
        raise


def remove():
    if not MANIFEST.exists():
        print("No owned installation recorded")
        return
    manifest = json.loads(MANIFEST.read_text())
    scripts = manifest.get("scripts", {str(SCRIPT): manifest.get("sha256")})
    for path, digest in scripts.items():
        target = Path(path)
        if target not in [SCRIPT, BRIDGE_SCRIPT]:
            raise RuntimeError("Unexpected script path in manifest; left untouched")
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() != digest:
            raise RuntimeError("Script changed; left untouched")
    # Only delete a rule whose name AND attached script match this experiment.
    result = applescript(f'''tell application id "com.apple.mail"
        if exists rule {apple_string(manifest['rule'])} then
            set probeRule to rule {apple_string(manifest['rule'])}
            set attachedPath to POSIX path of (run script of probeRule as alias)
            if attachedPath is not {apple_string(SCRIPT)} then error "Rule was changed; left untouched"
            if expression of first rule condition of probeRule is not {apple_string(manifest['prefix'])} then error "Condition changed; left untouched"
            delete probeRule
        end if
        return "removed"
    end tell''')
    assert result == "removed"
    for path in scripts:
        Path(path).unlink(missing_ok=True)
    MANIFEST.unlink()
    print("Removed owned Mail rule, script and manifest")


def status():
    print("Mail running:", applescript('application id "com.apple.mail" is running'))
    print("Owned installation:", MANIFEST.exists())
    print("Receiver socket:", SOCKET.exists())
    if MANIFEST.exists():
        manifest = json.loads(MANIFEST.read_text())
        print("Test subject:", manifest["prefix"])
        result = applescript(f'''tell application id "com.apple.mail"
            if not (exists rule {apple_string(manifest['rule'])}) then return "not configured"
            set attachedPath to POSIX path of (run script of rule {apple_string(manifest['rule'])} as alias)
            return attachedPath is {apple_string(SCRIPT)}
        end tell''')
        print("Rule attachment verified:", result)


def fixture_mbox():
    manifest = json.loads(MANIFEST.read_text())
    directory = CACHE / "Altillo-R01-Synthetic.mbox"
    directory.mkdir(exist_ok=True)
    message = EmailMessage()
    message["From"] = "Altillo prueba <synthetic@example.invalid>"
    message["To"] = "Local fixture <local@example.invalid>"
    message["Subject"] = manifest["prefix"] + " Acceso de prueba"
    message["Date"] = formatdate(localtime=True)
    message["Message-ID"] = "<" + uuid.uuid4().hex + "@altillo.example.invalid>"
    message.set_content("Tu código de acceso: 482913\nhttps://example.invalid/login?token=synthetic\n")
    (directory / "mbox").write_bytes(b"From synthetic@example.invalid " + time.asctime().encode() + b"\n" + message.as_bytes() + b"\n")
    print(directory)


def demo():
    if SOCKET.exists():
        with socket.socket(socket.AF_UNIX) as client:
            try:
                client.connect(str(SOCKET))
            except ConnectionRefusedError:
                pass  # UnixSocket.listen will remove the stale file safely.
            else:
                raise RuntimeError("A receiver is already running; left untouched")
    process = subprocess.Popen([str(HELPER), "listen", "--socket", str(SOCKET), "--duration", "35"])
    own_inode = None
    try:
        deadline = time.monotonic() + 3
        while not SOCKET.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        assert SOCKET.exists() and process.poll() is None, "Receiver did not start"
        own_inode = SOCKET.lstat().st_ino
        result = subprocess.run(["/usr/bin/osascript", str(CACHE / "Fixture.scpt")],
                                capture_output=True, timeout=5)
        assert result.returncode == 0 and result.stdout.strip() == b"true"
        process.wait(timeout=40)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=3)
        # On abnormal termination, remove only an owned dead socket, never another receiver's.
        if own_inode is not None and SOCKET.exists() and SOCKET.lstat().st_ino == own_inode:
            with socket.socket(socket.AF_UNIX) as client:
                try:
                    client.connect(str(SOCKET))
                except ConnectionRefusedError:
                    SOCKET.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "test", "demo", "prepare", "remove", "status", "listen", "fixture-mbox"])
    args = parser.parse_args()
    if args.command == "build":
        build()
    elif args.command == "listen":
        subprocess.run([str(HELPER), "listen", "--socket", str(SOCKET), "--duration", "300"], check=True)
    elif args.command == "fixture-mbox":
        fixture_mbox()
    else:
        globals()[args.command]()


if __name__ == "__main__":
    main()
