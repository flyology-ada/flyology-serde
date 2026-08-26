from __future__ import annotations

import pathlib
import hashlib
import tempfile
import unittest

import check_flyology_json_dependency as checker


GOOD_LOCK = '''
[[solution.state]]
crate = "flyology_json"
pinned = false
versions = "=0.1.0-dev"
[solution.state.release]
version = "0.1.0-dev"
[solution.state.release.origin]
commit = "3445b7540b89c3d1aa5c55d43b2817fab97710ae"
url = "git+https://github.com/flyology-ada/flyology-json.git"
[[solution.state.release.depends-on]]
gnat = ">=13 & <17"
[[solution.state]]
crate = "gnat"
'''
GOOD_RELEASE_SHA256 = hashlib.sha256(
    checker.release_manifest_from_text(GOOD_LOCK)
).hexdigest()


class Lock_Checker_Tests(unittest.TestCase):
    def check_text(self, text: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "alire.lock"
            path.write_text(text, encoding="utf-8")
            checker.check_lock(path, GOOD_RELEASE_SHA256)

    def test_accepts_exact_reviewed_state(self) -> None:
        self.check_text(GOOD_LOCK)

    def test_rejects_changed_commit(self) -> None:
        with self.assertRaisesRegex(ValueError, "source commit"):
            self.check_text(GOOD_LOCK.replace(checker.EXPECTED_COMMIT, "0" * 40))

    def test_rejects_pin(self) -> None:
        with self.assertRaisesRegex(ValueError, "unpinned"):
            self.check_text(GOOD_LOCK.replace("pinned = false", "pinned = true"))

    def test_rejects_added_dependency(self) -> None:
        changed = GOOD_LOCK.replace(
            'gnat = ">=13 & <17"',
            'gnat = ">=13 & <17"\n[[solution.state.release.depends-on]]\nfoo = "*"',
        )
        with self.assertRaisesRegex(ValueError, "release dependencies"):
            self.check_text(changed)

    def test_rejects_unexpected_solution_state(self) -> None:
        with self.assertRaisesRegex(ValueError, "unexpected solution states"):
            self.check_text(GOOD_LOCK + '[[solution.state]]\ncrate = "foo"\n')

    def test_rejects_release_metadata_change(self) -> None:
        changed = GOOD_LOCK.replace(
            '[solution.state.release]\n',
            '[solution.state.release]\ndescription = "changed"\n',
        )
        with self.assertRaisesRegex(ValueError, "release metadata SHA-256"):
            self.check_text(changed)

    def test_rejects_duplicate_json_state(self) -> None:
        duplicate = '''
[[solution.state]]
crate = "flyology_json"
pinned = false
versions = "=0.1.0-dev"
[solution.state.release]
version = "0.1.0-dev"
[solution.state.release.origin]
commit = "3445b7540b89c3d1aa5c55d43b2817fab97710ae"
url = "git+https://github.com/flyology-ada/flyology-json.git"
[[solution.state.release.depends-on]]
gnat = ">=13 & <17"
'''
        with self.assertRaisesRegex(ValueError, "expected one"):
            self.check_text(GOOD_LOCK + duplicate)


if __name__ == "__main__":
    unittest.main()
