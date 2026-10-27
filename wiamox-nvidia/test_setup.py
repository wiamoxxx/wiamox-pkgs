"""Tests for wiamox-nvidia's setup script. Fake pacman (keeps an installed
set in a file), wox, systemctl and mkinitcpio on PATH; WIAMOX_NVIDIA_ROOT
points the script's /usr, /etc and /var at a temp folder.
Run: python test_setup.py"""
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SETUP = os.path.join(HERE, "setup")

FAKE_PACMAN = r"""#!/bin/bash
db=$FAKE_DIR/installed; touch "$db"; echo "pacman $*" >>"$FAKE_DIR/calls"
op=$1; shift
case $op in
  -Qq) rc=0; for p; do grep -qx "$p" "$db" && echo "$p" || rc=1; done; exit $rc ;;
  -Rdd) shift; for p; do sed -i "/^$p\$/d" "$db"; done ;;
  -Rns) shift
        for p; do grep -qx "$p" "$db" || exit 1; done
        for p; do case " ${FAKE_REQUIRED:-} " in *" $p "*) exit 1 ;; esac; done
        for p; do sed -i "/^$p\$/d" "$db"; done ;;
  -S) [[ -n ${FAKE_S_FAIL:-} ]] && exit 1
      shift 2; for p; do grep -qx "$p" "$db" || echo "$p" >>"$db"; done ;;
esac
exit 0
"""
FAKE_WOX = '#!/bin/sh\necho "${FAKE_REC:-none}"\n'
FAKE_LOGGER = '#!/bin/sh\necho "${0##*/} $*" >>"$FAKE_DIR/calls"\n'

NEW = ["nvidia-open-dkms", "nvidia-utils", "lib32-nvidia-utils", "opencl-nvidia", "nvidia-settings"]
LEGACY = ["nvidia-580xx-dkms", "nvidia-580xx-utils", "lib32-nvidia-580xx-utils",
          "opencl-nvidia-580xx", "nvidia-580xx-settings"]
SHARED = ["libva-nvidia-driver", "nvidia-prime", "egl-wayland", "dkms", "linux-headers"]
# what the live ISO hands to the new system
LIVE = ["nvidia-open-dkms", "nvidia-utils", "egl-wayland", "dkms", "linux-headers"]


class Setup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.bin = os.path.join(self.tmp, "bin")
        self.root = os.path.join(self.tmp, "root")
        os.makedirs(self.bin)
        for name, body in (("pacman", FAKE_PACMAN), ("wox", FAKE_WOX),
                           ("systemctl", FAKE_LOGGER), ("mkinitcpio", FAKE_LOGGER)):
            with open(os.path.join(self.bin, name), "w") as f:
                f.write(body)
            os.chmod(os.path.join(self.bin, name), 0o755)
        share = os.path.join(self.root, "usr/share/wiamox-nvidia")
        os.makedirs(share)
        for name in ("new.packages", "legacy.packages"):
            shutil.copy(os.path.join(HERE, name), share)
        os.makedirs(os.path.join(self.root, "etc/modprobe.d"))
        self.write("etc/mkinitcpio.conf",
                   "MODULES=()\nHOOKS=(base udev autodetect microcode modconf kms keyboard keymap block filesystems fsck)\n")
        self.write("etc/modprobe.d/nvidia-utils.conf", "# WiamOX live: nouveau may load\n")
        self.set_installed(LIVE)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, rel, text):
        with open(os.path.join(self.root, rel), "w") as f:
            f.write(text)

    def read(self, rel):
        with open(os.path.join(self.root, rel)) as f:
            return f.read()

    def set_installed(self, pkgs):
        with open(os.path.join(self.tmp, "installed"), "w") as f:
            f.write("".join(p + "\n" for p in pkgs))

    def installed(self):
        with open(os.path.join(self.tmp, "installed")) as f:
            return set(f.read().split())

    def force(self, *names):
        for n in names:
            self.write(f"usr/share/wiamox-nvidia/force-{n}", "")

    def run_setup(self, *args, **env):
        e = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"],
                 WIAMOX_NVIDIA_ROOT=self.root, FAKE_DIR=self.tmp, **env)
        r = subprocess.run([SETUP, *(args or ("installer",))], env=e,
                           capture_output=True, text=True)
        calls_file = os.path.join(self.tmp, "calls")
        calls = []
        if os.path.exists(calls_file):
            with open(calls_file) as f:
                calls = f.read().splitlines()
        return r, calls

    def state(self):
        return self.read("var/lib/wiamox-nvidia/state")

    def test_new_card_keeps_live_driver_and_completes_it(self):
        r, calls = self.run_setup(FAKE_REC="new")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(set(NEW + SHARED) <= self.installed())
        self.assertFalse(set(LEGACY) & self.installed())
        self.assertIn("driver: new", self.state())
        self.assertTrue(any(c.startswith("systemctl enable nvidia-suspend") for c in calls))
        self.assertIn("mkinitcpio -P", calls)
        self.assertNotIn(" kms ", self.read("etc/mkinitcpio.conf"))
        self.assertIn("modconf keyboard", self.read("etc/mkinitcpio.conf"))
        self.assertFalse(os.path.exists(os.path.join(self.root, "etc/modprobe.d/nvidia-utils.conf")))

    def test_legacy_card_swaps_branch(self):
        r, calls = self.run_setup(FAKE_REC="legacy")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        inst = self.installed()
        self.assertTrue(set(LEGACY + SHARED) <= inst)
        self.assertFalse({"nvidia-open-dkms", "nvidia-utils"} & inst)
        self.assertIn("pacman -Rdd --noconfirm nvidia-open-dkms nvidia-utils", calls)
        self.assertIn("driver: legacy", self.state())

    def test_no_nvidia_removes_everything(self):
        r, calls = self.run_setup(FAKE_REC="none")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.installed(), set())
        self.assertIn("mkinitcpio -P", calls)
        self.assertFalse(any(c.startswith("systemctl") for c in calls))
        # kms stays for AMD/Intel
        self.assertIn(" kms ", self.read("etc/mkinitcpio.conf"))

    def test_nothing_to_do_runs_no_mkinitcpio(self):
        self.set_installed([])
        r, calls = self.run_setup(FAKE_REC="none")
        self.assertEqual(r.returncode, 0)
        self.assertNotIn("mkinitcpio -P", calls)

    def test_kepler_with_ai_keeps_what_cuda_needs(self):
        self.set_installed(LIVE + ["opencl-nvidia", "cuda"])
        r, _ = self.run_setup(FAKE_REC="nouveau", FAKE_REQUIRED="opencl-nvidia")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.installed(), {"opencl-nvidia", "cuda"})
        self.assertIn("AI Center", self.state())

    def test_forced_new_on_pascal_falls_back(self):
        self.force("new")
        r, _ = self.run_setup(FAKE_REC="legacy")
        self.assertIn("driver: legacy", self.state())
        self.assertIn("cannot drive this card", self.state())

    def test_forced_legacy_on_turing(self):
        self.force("legacy")
        self.run_setup(FAKE_REC="new")
        self.assertIn("driver: legacy", self.state())
        self.assertTrue(set(LEGACY) <= self.installed())

    def test_forced_driver_on_kepler_keeps_nouveau(self):
        self.force("legacy")
        self.run_setup(FAKE_REC="nouveau")
        self.assertIn("driver: nouveau", self.state())

    def test_forced_without_nvidia_card_installs_it(self):
        self.force("new")
        self.run_setup(FAKE_REC="none")
        self.assertIn("driver: new", self.state())

    def test_both_forced_means_auto(self):
        self.force("new", "legacy")
        self.run_setup(FAKE_REC="new")
        st = self.state()
        self.assertIn("mode: auto", st)
        self.assertIn("both 'force' options", st)

    def test_install_failure_never_fails_the_installer(self):
        r, _ = self.run_setup(FAKE_REC="legacy", FAKE_S_FAIL="1")
        self.assertEqual(r.returncode, 0)
        self.assertIn("installing the legacy driver failed", self.state())

    def test_bad_arguments(self):
        r, _ = self.run_setup("bogus")
        self.assertEqual(r.returncode, 2)
        r, _ = self.run_setup("install", "bogus")
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
