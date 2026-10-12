"""Exercise the fetch entry point with local pinned release assets on macOS."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ExternalBinaryFetchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ng2-fetch-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        source = Path(__file__).resolve().parent
        for name in ("fetch-external-binaries.sh", "lib-manifests.sh"):
            shutil.copy2(source / name, scripts / name)
        self.script = scripts / "fetch-external-binaries.sh"
        self.vendor = self.root / "Vendor" / "tool"
        self.vendor.mkdir(parents=True)
        self.asset = self.root / "release-tool"
        code = self.root / "main.c"
        code.write_text("int main(void) { return 0; }\n")
        subprocess.run(["xcrun", "clang", "-arch", "arm64", str(code), "-o", str(self.asset)], check=True)
        self.expected = hashlib.sha256(self.asset.read_bytes()).hexdigest()
        self.manifest = dict(project="fixture", release="v1", target="darwin-arm64",
                             asset=self.asset.name, url=self.asset.as_uri(),
                             archiveSHA256=self.expected, assetFormat="binary", binary="tool",
                             bundleSubpath="Helpers/Plugins", signIdentifier="fixture.tool")
        self.write_manifest()

    def write_manifest(self):
        (self.vendor / "manifest.json").write_text(json.dumps(self.manifest))

    def fetch(self):
        return subprocess.run(["sh", str(self.script)], capture_output=True, text=True)

    def test_binary_asset_is_verified_cached_and_refetched(self):
        result = self.fetch()
        self.assertEqual(result.returncode, 0, result.stderr)
        installed = self.vendor / "tool"
        self.assertEqual(installed.read_bytes(), self.asset.read_bytes())
        self.assertTrue(installed.stat().st_mode & 0o111)
        self.asset.unlink()
        cached = self.fetch()
        self.assertEqual(cached.returncode, 0, cached.stderr)
        self.assertIn("up to date", cached.stdout)
        installed.write_bytes(b"changed cache")
        missing = self.fetch()
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("download failed", missing.stderr)

    def test_hash_mismatch_never_installs(self):
        self.asset.write_bytes(b"changed upstream asset")
        result = self.fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA-256 mismatch", result.stderr)
        self.assertFalse((self.vendor / "tool").exists())

    def test_matching_hash_does_not_accept_non_macho(self):
        self.asset.write_bytes(b"not executable code")
        self.manifest["archiveSHA256"] = hashlib.sha256(self.asset.read_bytes()).hexdigest()
        self.write_manifest()
        result = self.fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a Mach-O binary", result.stderr)
        self.assertFalse((self.vendor / "tool").exists())

    def test_existing_tar_manifest_still_extracts_pinned_member(self):
        import tarfile
        archive = self.root / "release.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(self.asset, arcname="upstream_tool")
        self.manifest.pop("assetFormat")
        self.manifest.update(asset=archive.name, url=archive.as_uri(),
                             archiveMember="upstream_tool",
                             archiveSHA256=hashlib.sha256(archive.read_bytes()).hexdigest())
        self.write_manifest()
        result = self.fetch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.vendor / "tool").read_bytes(), self.asset.read_bytes())

    def test_unknown_format_is_rejected_even_with_cached_binary(self):
        self.assertEqual(self.fetch().returncode, 0)
        self.manifest["assetFormat"] = "zip"
        self.write_manifest()
        result = self.fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported assetFormat", result.stderr)


if __name__ == "__main__":
    unittest.main()
