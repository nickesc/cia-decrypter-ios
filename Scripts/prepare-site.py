#!/usr/bin/env python3
"""Stage the latest published release for the product website."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def prepare_site(distribution, output, site_url):
    source = json.loads((distribution / "source.json").read_text())
    app = source["apps"][0]
    version = app["versions"][0]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version["version"]):
        raise ValueError("Expected a numeric app release version.")
    ipa = distribution / "CIADecrypter.ipa"
    if ipa.stat().st_size != version["size"]:
        raise ValueError("The published IPA size does not match the source metadata.")

    tag = "v" + version["version"]
    release_path = f"releases/{tag}"
    release_url = f"{site_url.rstrip('/')}/{release_path}"
    release_directory = output / release_path
    release_directory.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ipa, release_directory / ipa.name)
    shutil.copyfile(distribution / "icon.png", release_directory / "icon.png")
    shutil.copyfile(ipa, output / ipa.name)
    source["iconURL"] = app["iconURL"] = f"{release_url}/icon.png"
    source["website"] = f"{site_url.rstrip('/')}/altstore/"
    version["downloadURL"] = f"{release_url}/{ipa.name}"
    (output / "source.json").write_text(json.dumps(source, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", "nickesc/cia-decrypter-ios"))
    parser.add_argument("--site-url", default=os.environ.get("SITE_URL", "https://nickesc.io/cia-decrypter-ios"))
    parser.add_argument("--output", type=Path, default=Path("homepage/static"))
    args = parser.parse_args()
    tag = subprocess.check_output([
        "gh", "release", "view", "--repo", args.repository,
        "--json", "tagName", "--jq", ".tagName",
    ], text=True).strip()
    with tempfile.TemporaryDirectory() as temp:
        subprocess.run([
            "gh", "release", "download", tag, "--repo", args.repository,
            "--pattern", "source.json", "--pattern", "icon.png",
            "--pattern", "CIADecrypter.ipa", "--dir", temp,
        ], check=True)
        distribution = Path(temp)
        source = json.loads((distribution / "source.json").read_text())
        if "v" + source["apps"][0]["versions"][0]["version"] != tag:
            raise ValueError("The release tag does not match its source metadata.")
        prepare_site(distribution, args.output, args.site_url)
    print(f"Staged {tag} source, icon, and IPA in {args.output}; nothing was deployed.")


if __name__ == "__main__":
    main()
