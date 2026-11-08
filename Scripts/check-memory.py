#!/usr/bin/env python3
"""Convert a local sample and fail if the macOS worker exceeds its memory budget."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("input", type=Path)
parser.add_argument("--aes", type=Path)
parser.add_argument("--boot9", type=Path)
parser.add_argument("--seeds", type=Path)
parser.add_argument("--max-rss-mb", type=int, default=128)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
binary = root / ".build/release/cia-convert"
if not binary.is_file():
    raise SystemExit("Run swift build -c release --product cia-convert first.")
(root / "build").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="memory-check-", dir=root / "build") as working:
    command = ["/usr/bin/time", "-l", str(binary), str(args.input), str(Path(working) / "output.3ds")]
    for name in ["boot9", "aes", "seeds"]:
        path = getattr(args, name)
        if path:
            command += [f"--{name}", str(path)]
    result = subprocess.run(command, capture_output=True, text=True)
    print(result.stdout.strip())
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)
    match = re.search(r"(\d+)\s+maximum resident set size", result.stderr)
    if not match:
        raise SystemExit("Could not read the macOS memory measurement.")
    measured = int(match.group(1)) / 1024**2
    print(f"Peak resident memory: {measured:.1f} MiB; budget: {args.max_rss_mb} MiB")
    if measured > args.max_rss_mb:
        raise SystemExit("Memory budget exceeded.")
    footprint = re.search(r"(\d+)\s+peak memory footprint", result.stderr)
    if footprint:
        measured_footprint = int(footprint.group(1)) / 1024**2
        print(f"Peak memory footprint: {measured_footprint:.1f} MiB")
        if measured_footprint > args.max_rss_mb:
            raise SystemExit("Memory footprint budget exceeded.")
