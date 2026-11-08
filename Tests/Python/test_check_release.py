import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ReleaseCheckTests(unittest.TestCase):
    def check_release(self, *, tags="", api_status=0, requested_tag=""):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            gh = directory / "gh"
            gh.write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_TAGS"\nexit "$TEST_API_STATUS"\n')
            gh.chmod(0o755)
            output = directory / "output"
            env = {
                **os.environ,
                "PATH": str(directory) + os.pathsep + os.environ["PATH"],
                "GITHUB_REPOSITORY": "example/converter",
                "GITHUB_OUTPUT": str(output),
                "REQUESTED_TAG": requested_tag,
                "TEST_TAGS": tags,
                "TEST_API_STATUS": str(api_status),
            }
            result = subprocess.run(
                ["bash", str(ROOT / "Scripts/check-release.sh"), "0.2.0"],
                env=env, capture_output=True, text=True,
            )
            values = dict(line.split("=", 1) for line in output.read_text().splitlines()) if output.exists() else {}
            return result, values

    def test_unpublished_app_version_creates_a_release(self):
        for tags in ["", "v0.1.0\nv0.2.01"]:
            with self.subTest(tags=tags):
                result, values = self.check_release(tags=tags)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(values, {"tag": "v0.2.0", "publish": "true"})

    def test_existing_version_skips_release(self):
        result, values = self.check_release(tags="v0.1.0\nv0.2.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(values, {"tag": "v0.2.0", "publish": "false"})

    def test_api_failure_does_not_authorize_a_release(self):
        result, values = self.check_release(api_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(values, {})

    def test_requested_tag_must_match_the_app_version(self):
        result, values = self.check_release(requested_tag="v0.1.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(values, {})


if __name__ == "__main__":
    unittest.main()
