# Nano for Legacy Windows <img src="./assets/logo.png" width="38">

This is a ported, standalone Windows build of [GNU Nano](https://www.nano-editor.org/),
that will run on legacy Windows such as Windows 2000, XP, 2003, Vista, and 7!

## About

Nano is a famous, easy-to-use and handy commandline text editor, traditionally for UNIX/Linux systems.  

The main Win32 support code (in [this patch](./patches/nano-win32.patch)) is based on [this repo](https://github.com/lhmouse/nano-win),
but unlike that repo, which uses an entire patched nano source tree, this repo prefers using
separated patch files and downloading + patching sources, which is also needed
for patching [ncurses](https://invisible-island.net/ncurses/) for Windows 2000+ support.  

<table>
  <tr>
    <td align="center" valign="middle"><img src="./assets/WinNT4Workstation_Logo.svg" height="64"></td>
    <td align="center" valign="middle"><img src="./assets/Win2000_Logo.svg" height="64"></td>
    <td align="center" valign="middle"><img src="./assets/WinXP_Logo.svg" height="64"></td>
  </tr>
</table>

## Downloads

The latest CI build can be found in releases [Here](https://github.com/Alex313031/nano/releases/tag/CI-Build),  
otherwise, grab the latest stable release [Here](https://github.com/Alex313031/nano/releases/latest).

## Building

I use [my MinGW fork](https://github.com/Alex313031/mingw-build#readme) to compile the releases.  
There is a GitHub runner [CI build](./.github/workflows/nano-legacy.yml) that uses this toolchain too.

This repo consists of a [build script](./build_nano.sh) and [collection of patches](./patches/).  
The [assets](./assets) dir contains images and text files for readmes or packaging.

The script downloads sources to `_build/src/`, and builds nano + ncurses in a per-arch named dir in `_build/build/$arch`.
Finally, it puts the finished .exe or .zip (if applicable) into `out/`.

```bash
 ./build_nano.sh x86 # Make Windows 32 bit build

 ./build_nano.sh x64 # Make Windows 64 bit build

 ./build_nano.sh x86 x64 # Make both 32 and 64 bit builds

 ./build_nano.sh x86 --package # Build, then package the .exe into a .zip

 ./build_nano.sh x86 --debug # Make a debug build (unstripped)

 ./build_nano.sh x86 --verbose # Show verbose build output

 ./build_nano.sh x86 --jobs 8 # Build using 8 make jobs

 ./build_nano.sh x86 --clean # Clean source and output dirs

 ./build_nano.sh --deps # Install build prerequisites (Debian/Ubuntu)

 ./build_nano.sh --version # Show script version

 ./build_nano.sh --help # See all build options
```

## License
This repo is licensed under the [GPL-3 License](./LICENSE.md), as is the original nano.
