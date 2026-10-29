# woxmon — WiamOX Monitor

The system monitor of **WiamOX**, by Wiam Khader. It runs in a terminal and
shows, live:

- **CPU**: total and per-core usage, frequency, temperatures, load average, uptime, battery
- **Memory**: used, available, cached, free, swap
- **Disks**: usage and read/write speed of every mounted disk
- **Network**: download and upload speed with graphs, per network device
- **GPU**: usage, memory, temperature, power and clock speed (NVIDIA, AMD and Intel) — shown by default
- **Processes**: sortable list or tree, filter, details of one process, send signals (terminate, kill, …), change nice values

![](packaging/com.wiamox.woxmon.svg)

## Use

Start it from the app launcher (**WiamOX Monitor**) or type `woxmon` in a terminal.

| Key | What it does |
|---|---|
| `Esc` or `m` | menu |
| `h` or `F1` | list of all keys |
| `o` or `F2` | options (theme, update speed, which boxes, graphs, …) |
| `1` `2` `3` `4` | show or hide the CPU, memory, network and process box |
| `5` … `0` | show or hide the boxes of GPU 1 … 6 |
| `p` / `P` | next / previous view preset |
| `f` or `/` | filter processes (start with `!` for a regular expression) |
| `↑` `↓`, `Enter` | select a process, show its details |
| `t` / `k` / `s` | terminate / kill / send a signal to the selected process |
| `e` | tree view |
| `+` / `-` | update faster / slower |
| `q` | quit |

The mouse works too: click the buttons in the box titles, scroll lists.

### GPU box

The GPU box is on by default. When there is no GPU, or the terminal is too
small for it (e.g. 80×24), it is hidden for that run only; your config keeps
it, so it comes back by itself in a bigger window or once the GPU driver is
loaded.

- **NVIDIA**: needs `nvidia-utils` (installed with the NVIDIA driver).
- **AMD**: works with the `amdgpu` driver; `rocm-smi-lib` adds more stats.
- **Intel**: reading the Intel GPU (and the CPU power in watts) needs rights
  a normal user does not have. If the Intel GPU box stays empty, run
  `sudo setcap cap_perfmon,cap_dac_read_search=+ep /usr/bin/woxmon`.
  This lets woxmon read performance counters and every file on the system
  (it only reads, it changes nothing); a package update removes it again.
  Running `sudo woxmon` works too.

## Files

| Path | What |
|---|---|
| `~/.config/woxmon/woxmon.conf` | settings (also changeable in the options menu, `o`) |
| `~/.config/woxmon/themes/` | your own `.theme` files |
| `/usr/share/woxmon/themes/` | themes for all users |
| `~/.local/state/woxmon.log` | log file |

`woxmon --default-config` prints every setting with an explanation.

## Command line

```
woxmon [-c file] [-d] [-f filter] [-l] [-p id] [-t] [-u ms] [--force-utf] [--themes-dir dir]
woxmon --default-config | --help | --version
```

See `woxmon --help` and `man woxmon`.

## Build

On WiamOX / Arch (needs `cmake`, a C++23 compiler such as GCC 14 or newer, `gtest`, `lowdown`, `librsvg`):

```sh
makepkg -s                       # package from the committed source
# or by hand:
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build build && ctest --test-dir build
./build/woxmon
```

The build needs no internet. woxmon lives in the `woxmon/` folder of the WiamOX
build workshop (wiamox-pkgs) and is built there with `scripts/build.sh woxmon`.

## License

Apache License 2.0 (see `LICENSE`). Bundled: `fmt` (MIT, `include/fmt/LICENSE.rst`)
and the Intel GPU reader in `source/linux/intel_gpu_top/` (MIT, see its file headers).
