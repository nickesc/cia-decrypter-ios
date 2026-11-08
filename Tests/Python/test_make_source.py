import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]


class SourceMetadataTests(unittest.TestCase):
    def run_generator(self, directory, *, tag="v0.1.0", extra=None):
        ipa = directory / "CIADecrypter.ipa"
        with zipfile.ZipFile(ipa, "w") as archive:
            archive.writestr("Payload/CIADecrypter.app/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": "xyz.batcomputer.ciadecrypter",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "3",
                "MinimumOSVersion": "26.0",
            }))
            if extra:
                archive.writestr(extra, b"synthetic test data")
        output = directory / "distribution/source.json"
        result = subprocess.run([
            sys.executable, str(ROOT / "Scripts/make-source.py"), str(ipa),
            "--repository", "example/converter", "--tag", tag, "--output", str(output),
        ], capture_output=True, text=True)
        return result, ipa, output

    def test_source_matches_packaged_version_size_and_release_assets(self):
        with tempfile.TemporaryDirectory() as temp:
            result, ipa, output = self.run_generator(Path(temp))
            self.assertEqual(result.returncode, 0, result.stderr)
            source = json.loads(output.read_text())
            self.assertEqual(source["website"], "https://example.github.io/converter/altstore/")
            app = source["apps"][0]
            self.assertEqual(app["bundleIdentifier"], "xyz.batcomputer.ciadecrypter")
            version = app["versions"][0]
            base = "https://github.com/example/converter/releases/download/v0.1.0"
            self.assertEqual(version["version"], "0.1.0")
            self.assertEqual(version["buildVersion"], "3")
            self.assertEqual(version["size"], ipa.stat().st_size)
            self.assertEqual(version["minOSVersion"], "26.0")
            self.assertEqual(version["downloadURL"], base + "/CIADecrypter.ipa")
            self.assertEqual(app["iconURL"], base + "/icon.png")
            self.assertTrue((output.parent / "icon.png").is_file())

    def test_mismatched_tag_writes_no_source(self):
        with tempfile.TemporaryDirectory() as temp:
            result, _, output = self.run_generator(Path(temp), tag="v0.2.0")
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_key_or_game_files_stop_release_metadata_generation(self):
        for extra in ["aes_keys.txt", "boot9.bin", "seeddb.bin", "game.cia", "game.3ds"]:
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as temp:
                result, _, output = self.run_generator(Path(temp), extra="Payload/CIADecrypter.app/" + extra)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
