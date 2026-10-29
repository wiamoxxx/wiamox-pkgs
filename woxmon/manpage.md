% woxmon(1) | User Commands
%
% 2026-10-29

# NAME

woxmon - WiamOX Monitor: shows the usage and stats of processor, memory, disks, network, GPU and processes.

# SYNOPSIS

**woxmon** [**-c** _file_] [**-d**] [**-f** _filter_] [**-l**] [**-p** _id_] [**-t**] [**-u** _ms_] [**\-\-force-utf**] [**\-\-themes-dir** _dir_]

**woxmon** [**\-\-default-config** | {**-h** | **\-\-help**} | {**-V** | **\-\-version**}]

# DESCRIPTION

**woxmon** (WiamOX Monitor) is the system monitor of WiamOX. It runs in a
terminal and shows the usage and stats of processor, memory, disks, network,
GPU (NVIDIA, AMD and Intel) and processes. Processes can be filtered, sorted,
shown as a tree, and sent signals.

Press **Esc** or **m** for the menu, **h** for the list of keys, **o** for the
options and **q** to quit. The keys **1** to **4** show or hide the CPU,
memory, network and process boxes, **5** to **0** the GPU boxes.

The GPU box is shown by default. Without a GPU, or when the terminal is too
small for it, it is hidden for that run; the config file keeps it, so it comes
back by itself.

# OPTIONS

The program follows the usual GNU command line syntax, with long options
starting with two dashes ('-'). A summary of options is included below.

**-c**, **\-\-config _file_**
:   Path to a config file.

**-d**, **\-\-debug**
:   Start in debug mode with additional logs and metrics.

**-f**, **\-\-filter _filter_**
:   Set an initial process filter.

**\-\-force-utf**
:   Force start even if no UTF-8 locale was detected.

**-l**, **\-\-low-color**
:   Disable true color, 256 colors only.

**-p**, **\-\-preset _id_**
:   Start with a preset (0-9).

**-t**, **\-\-tty**
:   Force tty mode with ANSI graph symbols and 16 colors only.

**\-\-no-tty**
:   Force disable tty mode.

**\-\-themes-dir _dir_**
:   Path to a custom themes directory. When specified, this directory takes priority over the default theme search paths.

**-u**, **\-\-update _ms_**
:   Set an initial update rate in milliseconds.

**\-\-default-config**
:   Print default config to standard output.

**-h**, **\-\-help**
:   Show summary of options.

**-V**, **\-\-version**
:   Show version of program.

# FILES

_~/.config/woxmon/woxmon.conf_
:   Config file, written on exit when settings changed (**$XDG_CONFIG_HOME** is used when set).

_~/.config/woxmon/themes/_
:   Your own **.theme** files.

_/usr/share/woxmon/themes/_
:   Themes installed for all users.

_~/.local/state/woxmon.log_
:   Log file (**$XDG_STATE_HOME** is used when set).

# BUGS

Send bug reports to Wiam@wiamox.com.

# SEE ALSO

**top**(1), **ps**(1), **free**(1)

# AUTHOR

**woxmon** is part of WiamOX by Wiam Khader.
