import json
from pathlib import Path
import runpy
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
prepare_site = runpy.run_path(str(ROOT / "Scripts/prepare-site.py"))["prepare_site"]


class SiteReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.distribution = Path(self.temp.name) / "distribution"
        self.distribution.mkdir()
        self.output = Path(self.temp.name) / "static"
        self.ipa = b"published IPA fixture"
        (self.distribution / "CIADecrypter.ipa").write_bytes(self.ipa)
        (self.distribution / "icon.png").write_bytes(b"published icon fixture")
        self.source = {
            "name": "CIA Decrypter",
            "iconURL": "https://github.com/example/release/icon.png",
            "apps": [{
                "bundleIdentifier": "xyz.batcomputer.ciadecrypter",
                "iconURL": "https://github.com/example/release/icon.png",
                "versions": [{
                    "version": "0.2.0", "buildVersion": "2",
                    "date": "2026-11-08T09:03:06+00:00", "size": len(self.ipa),
                    "downloadURL": "https://github.com/example/release/CIADecrypter.ipa",
                }],
            }],
            "news": [],
        }

    def stage(self):
        (self.distribution / "source.json").write_text(json.dumps(self.source))
        prepare_site(self.distribution, self.output, "https://example.com/app/")

    def test_source_and_assets_use_the_website_and_keep_published_metadata(self):
        self.stage()
        source = json.loads((self.output / "source.json").read_text())
        app = source["apps"][0]
        version = app["versions"][0]
        release = "https://example.com/app/releases/v0.2.0"
        self.assertEqual(source["iconURL"], release + "/icon.png")
        self.assertEqual(app["iconURL"], source["iconURL"])
        self.assertEqual(source["website"], "https://example.com/app/altstore/")
        self.assertEqual(version["downloadURL"], release + "/CIADecrypter.ipa")
        for key in ["version", "buildVersion", "date", "size"]:
            self.assertEqual(version[key], self.source["apps"][0]["versions"][0][key])
        self.assertEqual((self.output / "releases/v0.2.0/CIADecrypter.ipa").read_bytes(), self.ipa)
        self.assertEqual((self.output / "CIADecrypter.ipa").read_bytes(), self.ipa)
        self.assertEqual((self.output / "releases/v0.2.0/icon.png").read_bytes(), b"published icon fixture")

    def test_incorrect_ipa_size_stops_publication(self):
        self.source["apps"][0]["versions"][0]["size"] += 1
        with self.assertRaises(ValueError):
            self.stage()
        self.assertFalse((self.output / "source.json").exists())

    def test_invalid_version_cannot_escape_the_static_directory(self):
        self.source["apps"][0]["versions"][0]["version"] = "../../outside"
        with self.assertRaises(ValueError):
            self.stage()
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
