import unittest

from resolve_version import release_identity, resolve_version


class ResolveVersionTests(unittest.TestCase):
    def test_local_build_uses_pubspec(self):
        self.assertEqual(resolve_version("version: 0.1.3+3\n", {}), ("0.1.3", "3"))

    def test_tag_overrides_old_pubspec_on_every_platform(self):
        self.assertEqual(
            resolve_version("version: 0.1.3+1", {
                "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.3.0",
                "GITHUB_RUN_NUMBER": "52",
            }),
            ("0.3.0", "5201"),
        )

    def test_manual_build_supports_prerelease(self):
        self.assertEqual(
            resolve_version("version: 0.1.3+1", {"REQUESTED_VERSION": "v0.2.0-rc.1"}),
            ("0.2.0-rc.1", "1"),
        )

    def test_rejects_invalid_release_versions(self):
        for tag in ["vfoo", "v01.2.3", "v1.2", "v1.2.3-01", "v1.2.3;exit", "v1.2.3+5"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                resolve_version("version: 0.1.3+1", {
                    "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": tag,
                })

    def test_conflicting_manual_version_is_rejected(self):
        with self.assertRaises(ValueError):
            resolve_version("version: 0.1.3+1", {
                "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.3.0",
                "REQUESTED_VERSION": "0.4.0",
            })

    def test_main_and_manual_builds_have_unique_preview_release_tags(self):
        tag, preview = release_identity("0.2.0", "601", {"GITHUB_REF_TYPE": "branch"})
        self.assertEqual((tag, preview), ("build-0.2.0-601", "true"))
        self.assertFalse(tag.startswith("v"), "generated tags must not trigger another v* build")
        self.assertNotEqual(tag, release_identity("0.2.0", "602", {})[0])

    def test_only_stable_version_tags_are_official_releases(self):
        self.assertEqual(release_identity("0.2.0", "601", {
            "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.2.0",
        }), ("v0.2.0", "false"))
        self.assertEqual(release_identity("0.2.0-rc.1", "601", {
            "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.2.0-rc.1",
        }), ("v0.2.0-rc.1", "true"))


if __name__ == "__main__":
    unittest.main()
