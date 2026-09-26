#!/usr/bin/env python3
"""Lists user-facing strings of the macOS app that have no Spanish translation yet.

Reads the string keys the compiler extracted in the last build (`.stringsdata`) and compares them with
Apps/macOS/Resources/Localizable.xcstrings. Exits 1 if any key is missing, so release.sh and CI can stop on it.

    script/check-localization.py build/dd            # derivedData of a build of the Altillo scheme
    script/check-localization.py build/dd --json     # missing keys as JSON, key -> source file
"""
import glob
import json
import pathlib
import plistlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Apps/macOS/Resources/Localizable.xcstrings"


def extracted_keys(derived_data: str) -> dict[str, str]:
    keys: dict[str, str] = {}
    # Debug/Release builds keep them under Intermediates.noindex/Altillo.build/<config>/Altillo.build/, archives
    # under ArchiveIntermediates/Altillo/IntermediateBuildFilesPath/Altillo.build/<config>/Altillo.build/. The
    # second "Altillo.build" is the app target, which leaves out the hook, the widgets and the iOS app.
    pattern = f"{derived_data}/Build/Intermediates.noindex/**/*.stringsdata"
    for path in glob.glob(pattern, recursive=True):
        if pathlib.Path(path).parts.count("Altillo.build") < 2:
            continue
        with open(path, "rb") as handle:
            raw = handle.read()
        try:
            data = json.loads(raw)
        except ValueError:
            data = plistlib.loads(raw)
        for entry in data.get("tables", {}).get("Localizable", []):
            keys[entry["key"]] = pathlib.Path(path).stem
    return keys


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    keys = extracted_keys(args[0])
    if not keys:
        print(f"No .stringsdata under {args[0]}: build the Altillo scheme there first.", file=sys.stderr)
        return 2
    strings = json.loads(CATALOG.read_text())["strings"]
    missing = {
        key: source
        for key, source in sorted(keys.items())
        if strings.get(key, {}).get("shouldTranslate", True)
        and "es" not in strings.get(key, {}).get("localizations", {})
    }
    if "--json" in sys.argv:
        json.dump(missing, sys.stdout, ensure_ascii=False, indent=1)
        print()
    else:
        for key, source in missing.items():
            print(f"{source}: {key!r}")
        print(f"{len(missing)} of {len(keys)} strings without Spanish.", file=sys.stderr)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
