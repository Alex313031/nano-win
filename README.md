# Nano for Legacy Windows <img src="./assets/logo.png" width="38">

This is a script to build a standalone Windows build of [GNU Nano](https://www.nano-editor.org/),
that will run on legacy Windows such as Windows 2000, XP, Vista, etc.

## About

It is based on [this repo](https://github.com/lhmouse/nano-win#readme), but prefers using
separated [.patch files](./patches/) rather than a modified full source tree.

I use [my MinGW fork](https://github.com/Alex313031/mingw-build#readme) to compile the releases.

## Usage

```bash
 ./build_nano.sh x86 # Make Windows 32 bit build

 ./build_nano.sh x64 # Make Windows 64 bit build

 ./build_nano.sh x86 x64 # Make both 32 and 64 bit builds

 ./build_nano.sh x86 --package # Build, then package the .exe into a .zip

 ./build_nano.sh x86 --debug # Make a debug build (unstripped)

 ./build_nano.sh x86 --verbose # Show verbose build output

 ./build_nano.sh x86 --jobs 8 # Build using 8 make jobs

 ./build_nano.sh --deps # Install build prerequisites (Debian/Ubuntu)

 ./build_nano.sh --version # Show script version

 ./build_nano.sh --help # See all build options
```

### License

This repo is licensed under the [GPL-3 License](./LICENSE.md).
