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


class WoxTestBase(unittest.TestCase):
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
        calls = []
        if os.path.exists(self.log):
            with open(self.log) as f:
                calls = f.read().splitlines()
        # sudo logs itself and then runs pacman; keep only the pacman lines
        # unless the test asks for the sudo ones.
        return r, calls


class WoxPackageCommands(WoxTestBase):
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


class WoxGpu(WoxTestBase):
    """`wox gpu` against a fake sysfs (WOX_SYSFS)."""

    def gpu(self, cards, *args):
        sysfs = os.path.join(self.tmp.name, "sys")
        base = os.path.join(sysfs, "bus/pci/devices")
        os.makedirs(base, exist_ok=True)
        for i, (vendor, device) in enumerate(cards):
            d = os.path.join(base, f"0000:0{i}:00.0")
            os.makedirs(d)
            for name, value in (("class", "0x030000"), ("vendor", f"0x{vendor:04x}"),
                                ("device", f"0x{device:04x}"), ("boot_vga", "1" if i == 0 else "0")):
                with open(os.path.join(d, name), "w") as f:
                    f.write(value + "\n")
        return self.wox("gpu", *args, WOX_SYSFS=sysfs)

    def recommend(self, *cards):
        r, _ = self.gpu(cards, "--recommend")
        return r.stdout.strip()

    def test_branches(self):
        cases = {
            0x28A0: "new",      # RTX 4060 Laptop (Ada)
            0x1F82: "new",      # GTX 1650 (Turing, lowest new generation)
            0x1E04: "new",      # RTX 2080 Ti
            0x1DB1: "legacy",   # Tesla V100 (Volta)
            0x1C81: "legacy",   # GTX 1050 (Pascal)
            0x1D01: "legacy",   # GT 1030 (Pascal)
            0x1380: "legacy",   # GTX 750 Ti (Maxwell)
            0x1340: "legacy",   # 830M (first Maxwell ID)
            0x128B: "nouveau",  # GT 710 (Kepler)
            0x1004: "nouveau",  # GTX 780 (Kepler)
        }
        for device, want in cases.items():
            with self.subTest(device=hex(device)):
                self.assertEqual(self.recommend((0x10DE, device)), want)
                self.tearDown()
                self.setUp()

    def test_no_nvidia(self):
        self.assertEqual(self.recommend(), "none")
        self.tearDown(); self.setUp()
        self.assertEqual(self.recommend((0x8086, 0xA7A8), (0x1002, 0x73DF)), "none")

    def test_mixed_cards_pick_the_driver_for_both(self):
        # 580 also runs Turing+, the 615 driver does not run Pascal
        self.assertEqual(self.recommend((0x10DE, 0x1F08), (0x10DE, 0x1C81)), "legacy")
        self.tearDown(); self.setUp()
        self.assertEqual(self.recommend((0x10DE, 0x2204), (0x10DE, 0x1004)), "new")

    def test_report_hybrid_tip(self):
        r, _ = self.gpu([(0x8086, 0xA7A8), (0x10DE, 0x28A0)])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("Recommended: NVIDIA 615 driver", r.stdout)
        self.assertIn("prime-run", r.stdout)

    def test_report_kepler(self):
        r, _ = self.gpu([(0x10DE, 0x1004)])
        self.assertIn("nouveau", r.stdout.split("Recommended:")[1].splitlines()[0])

    def test_install_bad_mode(self):
        r, _ = self.gpu([(0x10DE, 0x28A0)], "install", "bogus")
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
