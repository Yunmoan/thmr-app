"""Protect the targeted, idempotent patch for file_picker's Kotlin opt-out."""
import unittest

from patch_android_plugin import fix_file_picker


class FilePickerCompatibilityTests(unittest.TestCase):
    def test_preserves_both_plugin_and_jvm_configuration_with_opt_out(self):
        original = """def isAgp9OrAbove = androidMajor >= 9
apply plugin: 'com.android.library'
if (!isAgp9OrAbove) {
    apply plugin: 'org.jetbrains.kotlin.android'
}
android {
    compileSdk flutter.compileSdkVersion
    if (!isAgp9OrAbove) {
        kotlinOptions { jvmTarget = '17' }
    }
}
"""
        patched = fix_file_picker(original)
        self.assertIn("project.findProperty('android.builtInKotlin')", patched)
        self.assertIn("'false'.equalsIgnoreCase", patched)
        self.assertEqual(patched.count('if (thmrUseLegacyKotlin)'), 2)
        self.assertIn("apply plugin: 'org.jetbrains.kotlin.android'", patched)
        self.assertIn("jvmTarget = '17'", patched)
        self.assertIn('compileSdk flutter.compileSdkVersion', patched)
        self.assertEqual(fix_file_picker(patched), patched)

    def test_new_plugin_scripts_without_the_bug_are_untouched(self):
        source = "apply plugin: 'com.android.library'\napply plugin: 'org.jetbrains.kotlin.android'\n"
        self.assertEqual(fix_file_picker(source), source)

    def test_changed_upstream_structure_fails_loudly(self):
        with self.assertRaises(ValueError):
            fix_file_picker('if (!isAgp9OrAbove) { apply plugin: "kotlin" }')


if __name__ == '__main__':
    unittest.main()
