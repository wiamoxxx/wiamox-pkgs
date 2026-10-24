#!/usr/bin/env bash
# Makes .config for the WiamOX 7.3 kernel in the current directory (a kernel
# source tree) and reports problems. Used by PKGBUILD prepare() and by
# `scripts/build.sh linux-7.3 --config-only`.
#
#   make-config.sh <linux-7.3 package dir> [fragments|full] [reference-config]
#
# fragments: x86_64_defconfig + wiamox-base.config + wiamox-drivers.config
# full:      <package dir>/config as it is
# The reference config (default <package dir>/config, if it exists) is only
# used to print what changed.
set -euo pipefail

pkgdir=$(cd "$1" && pwd)
mode=${2:-fragments}
ref=${3:-$pkgdir/config}
log=${MERGE_LOG:-/dev/null}

[[ -f Makefile && -x scripts/kconfig/merge_config.sh ]] ||
  { echo "make-config.sh must run inside a kernel source tree" >&2; exit 1; }

case $mode in
  fragments)
    make -s x86_64_defconfig
    # Reports every value it overrides, thousands of lines: keep it in a log.
    scripts/kconfig/merge_config.sh -m .config \
      "$pkgdir/wiamox-base.config" "$pkgdir/wiamox-drivers.config" >"$log"
    ;;
  full)
    [[ -f $pkgdir/config ]] || { echo "No $pkgdir/config (WIAMOX_KERNEL73_CONFIG=full needs one)." >&2; exit 1; }
    cp "$pkgdir/config" .config
    ;;
  *)
    echo "WIAMOX_KERNEL73_CONFIG must be 'fragments' or 'full', not '$mode'." >&2
    exit 1
    ;;
esac
make -s olddefconfig

if [[ $mode == fragments ]]; then
  echo "Fragment settings the kernel did not accept (missing dependency, or the option is gone in this version):"
  # Last fragment wins, as in merge_config.sh.
  awk '
    FNR == 1 { file++ }
    file <= ARGC - 2 {
      if (match($0, /^CONFIG_[A-Za-z0-9_]+=/)) want[substr($0, 1, RLENGTH - 1)] = substr($0, RLENGTH + 1)
      else if (match($0, /^# CONFIG_[A-Za-z0-9_]+ is not set/)) want[$2] = "n"
      next
    }
    /^CONFIG_/ { i = index($0, "="); have[substr($0, 1, i - 1)] = substr($0, i + 1) }
    END {
      for (k in want) {
        got = (k in have) ? have[k] : "n"
        if (want[k] != got) { printf "  %s: wanted %s, got %s\n", k, want[k], got; n++ }
      }
      if (!n) print "  (none)"
    }
  ' "$pkgdir/wiamox-base.config" "$pkgdir/wiamox-drivers.config" .config | sort
fi

# Things the 7.3 config must never contain: the point of the lean config.
echo "Legacy options that came back on (should be none):"
bad=$(grep -E '^CONFIG_(E1000|ATL1C|TIGON3|USB_OHCI_HCD|ATA_SFF|PATA_[A-Z0-9_]+|BLK_DEV_FD|PARPORT|FIREWIRE|PCMCIA|ISA_BUS|X86_ACPI_CPUFREQ|HID_WIIMOTE|SND_HDA_CODEC_(VIA|SIGMATEL|CA0110|CA0132|ANALOG)|ACPI_TOSHIBA|SONY_LAPTOP|FUJITSU_LAPTOP|PANASONIC_LAPTOP|DRM_RADEON|DRM_GMA500|FB_VESA|FB_EFI)=' .config | grep -v '^CONFIG_PATA_TIMINGS=' || true)
if [[ -n $bad ]]; then sed 's/^/  /' <<<"$bad"; else echo "  (none)"; fi

if [[ -f $ref ]]; then
  echo "Differences from the reference config $(basename "$ref") (compiler/toolchain lines hidden):"
  scripts/diffconfig "$ref" .config |
    grep -vE '(_VERSION|^.?(CC|AS|LD|RUSTC|PAHOLE|TOOLS|OPENSSL)_(HAS|CAN|IS|SUPPORTS)_|^.?GCC_PLUGIN|^.?(KSTACK_ERASE|RANDSTRUCT_))' || :
fi

printf 'Result: %s options =y, %s options =m\n' \
  "$(grep -c '=y$' .config)" "$(grep -c '=m$' .config)"
