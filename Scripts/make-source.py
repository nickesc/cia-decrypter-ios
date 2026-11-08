#!/usr/bin/env python3
"""Generate AltStore Classic metadata from the actual packaged IPA."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("ipa", type=Path)
parser.add_argument("--repository", default="nickesc/cia-decrypter-ios")
parser.add_argument("--output", type=Path, default=Path("build/distribution/source.json"))
args = parser.parse_args()

with zipfile.ZipFile(args.ipa) as archive:
    forbidden = [name for name in archive.namelist() if Path(name).name.lower() in {"aes_keys.txt", "seeddb.bin", "boot9.bin", "boot9_prot.bin"} or name.lower().endswith((".cia", ".3ds", ".cci")) or "/Secrets/" in name]
    if forbidden:
        raise SystemExit("The IPA contains key files or game data; do not publish it.")
    info_paths = [name for name in archive.namelist() if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
    if len(info_paths) != 1:
        raise SystemExit("Expected exactly one app in the IPA.")
    info = plistlib.loads(archive.read(info_paths[0]))
    if info["CFBundleIdentifier"] != "com.nickesc.ciadecrypter":
        raise SystemExit("Unexpected bundle identifier.")
    if any(name.endswith(".appex/Info.plist") for name in archive.namelist()):
        raise SystemExit("Audit extension permissions before publishing this IPA.")
    entitlements = []
    privacy = {name: value for name, value in info.items() if name.startswith("NS") and name.endswith("UsageDescription")}

version = info["CFBundleShortVersionString"]
owner, repository = args.repository.split("/", 1)
base = f"https://{owner}.github.io/{repository}"
source = {
    "name": "CIA Decrypter for iOS",
    "subtitle": "On-device CIA conversion",
    "iconURL": f"{base}/icon.png",
    "website": f"https://github.com/{args.repository}",
    "tintColor": "#DB3340",
    "apps": [{
        "name": "CIA Decrypter for iOS",
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "Nick Escobar",
        "localizedDescription": "Convert base-game CIA files into decrypted .3ds files on iPhone and iPad. Includes queued conversions, local key imports, background processing, and export to Files.",
        "iconURL": f"{base}/icon.png",
        "category": "utilities",
        "versions": [{
            "version": version,
            "buildVersion": info["CFBundleVersion"],
            "date": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "downloadURL": f"https://github.com/{args.repository}/releases/download/v{version}/{args.ipa.name}",
            "size": args.ipa.stat().st_size,
            "minOSVersion": info["MinimumOSVersion"],
        }],
        "appPermissions": {"entitlements": entitlements, "privacy": privacy},
    }],
    "news": [],
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(source, indent=2) + "\n")
icon = Path(__file__).resolve().parent.parent / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
(args.output.parent / "icon.png").write_bytes(icon.read_bytes())
print(f"Prepared {args.output}; no files were uploaded or published.")
