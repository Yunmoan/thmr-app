import unittest

from resolve_version import resolve_version


class ResolveVersionTests(unittest.TestCase):
    def test_local_build_uses_pubspec(self):
        self.assertEqual(resolve_version("version: 0.1.2+3\n", {}), ("0.1.2", "3"))

    def test_tag_overrides_old_pubspec_on_every_platform(self):
        self.assertEqual(
            resolve_version("version: 0.1.2+1", {
                "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.3.0",
                "GITHUB_RUN_NUMBER": "52",
            }),
            ("0.3.0", "5201"),
        )

    def test_manual_build_supports_prerelease(self):
        self.assertEqual(
            resolve_version("version: 0.1.2+1", {"REQUESTED_VERSION": "v0.2.0-rc.1"}),
            ("0.2.0-rc.1", "1"),
        )

    def test_rejects_invalid_release_versions(self):
        for tag in ["vfoo", "v01.2.3", "v1.2", "v1.2.3-01", "v1.2.3;exit", "v1.2.3+5"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                resolve_version("version: 0.1.2+1", {
                    "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": tag,
                })

    def test_conflicting_manual_version_is_rejected(self):
        with self.assertRaises(ValueError):
            resolve_version("version: 0.1.2+1", {
                "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.3.0",
                "REQUESTED_VERSION": "0.4.0",
            })


if __name__ == "__main__":
    unittest.main()
