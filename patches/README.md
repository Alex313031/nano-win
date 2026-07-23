# Patches

Patches for **nano** and **ncurses** that add Windows support (down to **Windows
NT 4.0**) and adjust some default behaviors. They are applied on top of the vanilla
upstream sources fetched by [`build_nano.sh`](../build_nano.sh).

Each subdir has two quilt-style **series** files listing which patches apply, in
order, for each target:

- `series_win.txt` — Windows builds (the full set).
- `series_linux.txt` — `--linux` builds (only the platform-neutral enhancements; the
  Win32 port, resource, and NT-compat shims are skipped). The ncurses Linux series is
  empty — Linux builds plain upstream ncurses.

## nano (`patches/nano/`)

Applied with `git apply`, in `series` order (`nano-win32` must be first).

| Patch | Win | Linux | What it does |
|-------|:---:|:-----:|--------------|
| `nano-win32.patch` | ✔ | | Core Win32 port, based on [lhmouse/nano-win](https://github.com/lhmouse/nano-win): console I/O, path handling, Vim-style lock files, Alt-as-Meta, UNIX-style line endings, and the `win32.h` include header. Also adds the **NT 4.0-safe dynamic shims** `GetConsoleWindowEx`, `IsUserAnAdminEx`, and `PathIsRelativeEx` — functions absent on base NT 4.0 (`GetConsoleWindow`, `IsUserAnAdmin`, shlwapi's `PathIsRelativeA`) are resolved at runtime instead of statically imported, so the binary still loads there. |
| `win32-resize.patch` | ✔ | | Re-layout on a console resize. Windows has no `SIGWINCH`, so this turns the win32 console driver's `KEY_RESIZE` (see ncurses `win32con-resize.patch`) into nano's `the_window_resized` trigger. Windows-only (`#ifdef _WIN32`). |
| `rc-icon.patch` | ✔ | | Adds `src/nano.rc` and the `windres` rule in `src/Makefile.am` — compiles in the app icon + version resource. |
| `version-info.patch` | ✔ | | Adds `src/version.c` / `src/version.h`: version macros consumed by `nano.rc`, plus runtime getters for the nano version and the host OS (the latter is appended to `nano --version`). |
| `time32-compat.patch` | ✔ | | Provides `_time32()` on 64-bit Windows. XP x64 / Server 2003's `msvcrt.dll` exports `_time64` but not `_time32` (which the mingw-w64 x64 runtime references); this delegates to `_time64`. x64-only. |
| `default-crlf.patch` | ✔ | | New files default to DOS/CRLF line endings. Guarded with `#if defined(_WIN32)`, so it is a no-op on Linux. |
| `nanorc.patch` | ✔ | ✔ | A `.nanorc` next to the executable is used exclusively, overriding all other locations, so nano runs as a portable app. Locates the executable via `GetModuleFileNameA` on Windows and `readlink("/proc/self/exe")` on Linux (`#ifdef`-guarded). |
| `linenumbers-default.patch` | ✔ | ✔ | Show line numbers by default (`unset linenumbers` in `.nanorc` to disable). |
| `interface.patch` | ✔ | ✔ | Colorful compiled-in interface defaults, without needing an nanorc file. |
| `syntax-colors.patch` | ✔ | ✔ | Richer C/C++ syntax highlighting (`c.nanorc`). |
| `save-prompt.patch` | ✔ | ✔ | Appends `(Y/N/^C)` to the exit "Save modified buffer?" prompt so the choices show inline. (Idea from [okibcn/nano-for-windows](https://github.com/okibcn/nano-for-windows).) |

## ncurses (`patches/ncurses/`)

Applied with `patch(1)` (ncurses is a plain tarball, not a git repo). **Windows only** —
the Linux build uses upstream ncurses unpatched.

| Patch | What it does |
|-------|--------------|
| `winver.patch` | Targets the win32 console driver at `WINVER=0x0400` (Windows NT 4.0) instead of `0x0501` (Windows XP). |
| `win2k.patch` | Resolves `AttachConsole()` — an XP+ API, absent on NT 4.0 and 2000 — dynamically, so its missing static import no longer stops the binary from loading on pre-XP Windows. (A console app already owns its console there, so the attach is unneeded anyway.) |
| `win32con-resize.patch` | Makes console resizes actually re-layout the app. Windows has no `SIGWINCH`, and this ncurses is built without `USE_SIZECHANGE` (so its auto-resize machinery is compiled out). The patch enables `ENABLE_WINDOW_INPUT`, surfaces `WINDOW_BUFFER_SIZE_EVENT`, and in `_nc_console_read` re-queries the console and calls `resize_term()` to update `LINES`/`COLS` before returning `KEY_RESIZE` (which nano acts on via `win32-resize.patch`). Only fires on a real size change, so it neither flickers nor feeds back. Covers where a window resize changes the screen buffer: modern (Win 8+) consoles, and explicit screen-buffer-size changes (console Properties) on legacy ones. |
| `win32con-legacy-resize.patch` | Drag-to-resize on **legacy** consoles (Win 2000–7). There a window drag changes only the viewport (`srWindow`), which — with nano on an alternate screen buffer — isn't reported and posts no event, so the driver polls the visible size derived from the console **window's client rectangle ÷ font cell size** and calls `resize_term()` + returns `KEY_RESIZE` once the drag **settles** (debounced, no flicker). The poll covers **both** wait paths: timed waits (`_nc_console_twait`, capped at the poll interval) and plain blocking reads (`_nc_console_read` waits with a timeout + polls instead of parking in `ReadConsoleInput`, which a drag would never wake — nano's idle key wait is exactly such a blocking read). To also allow **growing** the window (a legacy console clamps the window to the screen buffer, and nano's private buffer starts window-sized), the buffer is enlarged to the display's maximum when polling arms — scrollbars show while nano runs; the shell's own buffer is untouched and the window snaps back to it on exit. Buffer-size events are swallowed while polling is active (the visible size is authoritative), and the size estimate **self-calibrates** on the first poll against the then-known `LINES`/`COLS`, absorbing scrollbar/border/font-DPI quirks. Gated to pre-6.2 Windows via `GetVersion()` so the modern path is untouched; window/font APIs resolved dynamically so NT 4.0 still loads (drag-resize unavailable there — use Properties). |

## Regenerating a patch

Apply the series onto a pristine v9.1 tree, edit the source, then
`git diff` the result back into the patch (preserving its free-text header). See the
build script's `apply_series`/`apply_patches` for how the series are consumed.
