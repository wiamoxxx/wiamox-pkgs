"""Tests for the wox package commands. Fake `sudo` and `pacman` on PATH log
their arguments, so nothing touches the real system. Run: python test_wox.py"""
import os
import subprocess
import sys
import tempfile
import unittest

WOX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wox")

FAKE_SUDO = '#!/bin/sh\necho "sudo $*" >>"$WOX_TEST_LOG"\nexec "$@"\n'
FAKE_PACMAN = """#!/bin/sh
echo "pacman $*" >>"$WOX_TEST_LOG"
case "$1" in
  -Qq) [ "$2" = installed-pkg ] ;;
  -Qdtq) [ -n "$WOX_TEST_ORPHANS" ] && printf '%s\\n' $WOX_TEST_ORPHANS || exit 1 ;;
  *) exit "${WOX_TEST_RC:-0}" ;;
esac
"""


class WoxPackageCommands(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        for name, body in (("sudo", FAKE_SUDO), ("pacman", FAKE_PACMAN)):
            path = os.path.join(self.tmp.name, name)
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, 0o755)
        self.log = os.path.join(self.tmp.name, "log")

    def tearDown(self):
        self.tmp.cleanup()

    def wox(self, *args, **env):
        e = dict(os.environ, PATH=self.tmp.name + os.pathsep + os.environ["PATH"],
                 WOX_TEST_LOG=self.log, **env)
        r = subprocess.run([sys.executable, WOX, *args], env=e, capture_output=True,
                           text=True, stdin=subprocess.DEVNULL)
        calls = open(self.log).read().splitlines() if os.path.exists(self.log) else []
        # sudo logs itself and then runs pacman; keep only the pacman lines
        # unless the test asks for the sudo ones.
        return r, calls

    def pacman_calls(self, calls):
        return [c for c in calls if c.startswith("pacman ")]

    def assert_runs(self, args, expected, sudo=True):
        r, calls = self.wox(*args)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn(expected, self.pacman_calls(calls))
        if os.geteuid() != 0:
            self.assertEqual(any(c.startswith("sudo ") for c in calls), sudo)
        self.assertIn("-> ", r.stdout)       # shows the real command first

    def test_install(self):
        self.assert_runs(["install", "firefox", "vlc"], "pacman -Sy firefox vlc")

    def test_install_short(self):
        self.assert_runs(["i", "firefox"], "pacman -Sy firefox")

    def test_remove(self):
        self.assert_runs(["remove", "vlc"], "pacman -Rns vlc")
        self.assert_runs(["rm", "vlc"], "pacman -Rns vlc")

    def test_update(self):
        self.assert_runs(["update"], "pacman -Syu")
        self.assert_runs(["up"], "pacman -Syu")

    def test_search_without_sudo(self):
        self.assert_runs(["search", "fire"], "pacman -Ss fire", sudo=False)
        self.assert_runs(["s", "fire"], "pacman -Ss fire", sudo=False)

    def test_list(self):
        self.assert_runs(["list"], "pacman -Qe", sudo=False)

    def test_info_installed_and_repo(self):
        r, calls = self.wox("info", "installed-pkg", "repo-pkg")
        self.assertEqual(r.returncode, 0)
        self.assertIn("pacman -Qi installed-pkg", calls)
        self.assertIn("pacman -Si repo-pkg", calls)

    def test_clean_with_orphans(self):
        r, calls = self.wox("clean", WOX_TEST_ORPHANS="libfoo libbar")
        self.assertEqual(r.returncode, 0)
        self.assertIn("pacman -Rns libfoo libbar", calls)

    def test_clean_without_orphans(self):
        r, calls = self.wox("clean")
        self.assertEqual(r.returncode, 0)
        self.assertIn("No orphans", r.stdout)
        self.assertEqual(calls, ["pacman -Qdtq"])

    def test_missing_args(self):
        for verb in ("install", "remove", "search", "info"):
            r, calls = self.wox(verb)
            self.assertEqual(r.returncode, 2, verb)
            self.assertEqual(calls, [], verb)

    def test_exit_code_passed_through(self):
        r, _ = self.wox("install", "nope", WOX_TEST_RC="1")
        self.assertEqual(r.returncode, 1)

    def test_flags_passed_through(self):
        self.assert_runs(["install", "--needed", "git"], "pacman -Sy --needed git")

    def test_help_and_unknown(self):
        r, _ = self.wox("help")
        self.assertEqual(r.returncode, 0)
        self.assertIn("wox install", r.stdout)
        r, _ = self.wox("bogus")
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
