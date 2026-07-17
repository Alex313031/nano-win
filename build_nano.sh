#!/bin/bash -e

# Copyright (c) 2026 Alex313031.

# Build a Windows nano that will run on legacy versions of Windows
# (Windows NT4, 2000, XP, Server 2003, and Vista; Win7+ work upstream), or Linux.
# It does NOT use MSYS2: it drives a custom, legacy-Windows-compatible msvcrt-based
# mingw cross toolchain, fetching nano (git) and ncurses (tarball) from scratch.

SCRIPTNAME=$(basename "$0")
SCRIPTVER="1.1.6"

# Colors
YEL='\033[1;33m'  # Yellow
CYA='\033[1;96m'  # Cyan
RED='\033[1;31m'  # Red
GRE='\033[1;32m'  # Green
C0='\033[0;00m'   # Reset Text
BOLD='\033[1;37m' # Bold Text
ULINE='\033[4m'   # Underline Text

export HERE=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

JOBS=$(getconf _NPROCESSORS_ONLN) # Default to num processors

# Bump ncurses/nano version here. NANO_VER is a vanilla upstream tag (or branch);
# the Windows support is layered on top from the patches/ dir.
NANO_VER="v9.1"
NCURSES_VER="6.6"

# Change upstream URLs here
NANO_URL="https://github.com/lhmouse/nano-win" # vanilla nano; the v9.1 tag == savannah upstream
NCURSES_ARCHIVE="ncurses-${NCURSES_VER}.tar.gz"
NCURSES_URL="https://invisible-island.net/archives/ncurses/${NCURSES_ARCHIVE}"

# Where finished executables/.zips land
OUT_DIR="${HERE}/out"
# Where sources are cloned, building is done, and log files live.
SRC_DIR="${HERE}/_build"
# Where building is performed, subdir of SRC_DIR.
BUILD_DIR="${SRC_DIR}/build"
# Where the vanilla nano and ncurses sources are fetched and patched (both under
# SRC_DIR/src, created at runtime; not tracked in the repo). These default to the
# Windows trees and are pointed at the Linux trees after arg parsing (--linux), so
# the two targets keep independent patched sources and need no clean to switch.
NANO_SRC="${SRC_DIR}/src/nano-win"
NCURSES_SRC="${SRC_DIR}/src/ncurses-win"
# Build log: execute() writes command output here instead of the console
# unless --verbose is given.
LOG_FILE="${BUILD_DIR}/build.log"

# Build config defaults
IS_DEBUG=false # Default is release mode
USE_LLVM=false # When true, build with LLVM/MinGW toolchain instead of GCC/MinGW.
IS_TINY=false # Default is a full-featured build
WIN32_WINNT=0x0400 # Minimum target Windows ver

error_exit() {
  local error_msg="$1"
  shift 1

  if [ "$error_msg" ]; then
    printf "${RED}%s${C0}\n" "$error_msg" >&2
  else
    printf "${RED}An error occured.${C0}\n" >&2
  fi
  exit 1
}

arg_error() {
  local error_msg="$1"
  shift 1

  error_exit "$error_msg, see --help for options" "$error_msg"
}

log() {
  # Print a progress message to the console (interpreting color codes and \n),
  # and append a color-stripped copy to the build log so it captures the flow too.
  printf "$1"
  printf "$1" | sed -E 's/\x1b\[[0-9;]*m//g' >> "${LOG_FILE}"
}

execute() {
  local info_msg="$1"
  local error_msg="$2"
  shift 2

  if [ ! "$error_msg" ]; then
    error_msg="error"
  fi

  if [ "$info_msg" ]; then
    printf "${CYA} %s ${C0}\n" "$info_msg"
  fi
  # In verbose mode, stream command output to the console; otherwise send it to
  # the build log so the console shows only the progress messages above.
  if [ "$VERBOSE" == "1" ]; then
    "$@" 2>&1 || error_exit "$error_msg"
  else
    "$@" >> "${LOG_FILE}" 2>&1 || error_exit "$error_msg (see ${LOG_FILE})"
  fi
}

# Apply the patches listed in a quilt-style series file, in order. This is the
# single source of truth for patch order: the per-subdir 'series' files drive it,
# so adding/reordering a patch only means editing that file. Blank lines and lines
# beginning with '#' are skipped; only the first whitespace-separated field of a
# line is used, so trailing quilt options/comments are tolerated.
#   $1 = dir holding the patches and its 'series' file
#   $2 = target source tree to patch
#   $3 = apply method: 'git' (git apply, for a git repo) or 'patch' (patch -p1)
apply_series() {
  local dir="$1" target="$2" method="$3"
  if [ "$TARGET_LINUX" == "1" ]; then
    local series="${dir}/series_linux.txt"
  else
    local series="${dir}/series_win.txt"
  fi
  [ -f "${series}" ] || error_exit "apply_series: no series file at ${series}"
  local name _rest
  # `|| [ -n "$name" ]` processes a final line that lacks a trailing newline.
  while read -r name _rest || [ -n "${name}" ]; do
    [ -z "${name}" ] && continue             # skip blank lines
    case "${name}" in \#*) continue ;; esac  # skip comment lines
    if [ "${method}" = "git" ]; then
      execute "Applying ${name}..." "Failed to apply ${name}" \
          git -C "${target}" apply --reject "${dir}/${name}"
    else
      execute "Applying ${name}..." "Failed to apply ${name}" \
          patch -N -p1 -d "${target}" -i "${dir}/${name}"
    fi
  done < "${series}"
}

show_help() {
  cat <<EOF
Usage:
  $SCRIPTNAME <arch> [options]
 - Builds GNU nano for legacy Windows (or Linux, with --linux).

Archs:
  i686 | x32 | x86 | -32     - Windows 32-bit (Windows NT 4.0+) / 32-bit Linux
  x86_64 | amd64 | x64 | -64 - Windows 64-bit (Windows XP x64/Server 2003+) / 64-bit Linux

Options:
  -h, --help                  Show this help.
  --version                   Show script version.
  --deps                      Install prerequisites for using this script (Ubuntu/Debian only).
  -j <count>, --jobs <count>  Override make job count. (default: $JOBS)
  -d, --debug                 Create a debug build (default is release mode).
  -t, --tiny                  Build a minimal nano (--enable-tiny; drops color, line numbers, nanorc, etc.).
  -v, --verbose               Show verbose build output.
  -p, --package               After a successful build, package nano + support files into a zip.
  -l, --llvm                  Build with Clang (LLVM/MinGW) instead of GCC/MinGW toolchain.
  --linux                     Make a static Linux build instead. Requires gcc on path.
  --patch                     Fetch and patch the sources, then stop (no configure/build; no arch needed).
  -c, --clean                 Remove build output and fetched sources (out/ + _build/).
  --distclean                 Remove build output (out/ + build tree), keeping fetched sources.
EOF
}

show_version() {
  printf "\n ${BOLD} %s Version: ${ULINE}%s${C0}\n\n" "$SCRIPTNAME" "$SCRIPTVER"
  exit 0
}

install_deps() {
  if ! command -v apt-get >/dev/null; then
    error_exit "--deps only supports apt-based systems (Ubuntu/Debian); install the prerequisites manually"
  fi
  # use sudo only when not already root (e.g. plain CI containers lack sudo)
  local sudo=""
  [ "$(id -u)" -ne 0 ] && sudo="sudo"

  printf "${GRE}Installing dependencies for $SCRIPTNAME...${C0}\n"
  $sudo apt-get update || error_exit "apt-get update failed"
  # autoconf/automake/autopoint/pkg-config/gettext are needed because a fresh
  # nano clone builds "from git" (configure requires pkg.m4 + msgfmt, autogen.sh
  # needs the autotools); git is needed to clone the source.
  $sudo apt-get install -y \
        build-essential g++-multilib zip unzip wget tar git patch \
        autoconf automake autopoint pkg-config gettext \
        mingw-w64 mingw-w64-i686-dev mingw-w64-x86-64-dev mingw-w64-tools \
      || error_exit "Failed to install dependencies"
  printf "${GRE}Done installing dependencies!${C0}\n"
}

# Zip an already-installed arch's nano plus its support files. The staging
# dir lives under the arch's build dir; the resulting archive is dropped in out/.
packageNano() {
  local arch="$1" prefix="$2"

  if [ "$TARGET_LINUX" == "1" ]; then
    local osname="Linux"
    local fileext=""
    local _builddir="${BUILD_DIR}/linux_${arch}"
  else
    local osname="Windows"
    local fileext=".exe"
    local _builddir="${BUILD_DIR}/win_${arch}"
  fi
  if [ "$arch" = "x86" ]; then
    if [ "$TARGET_LINUX" == "1" ]; then
      local zipname="nano_linux_x86"
    else
      local zipname="nano_win32"
    fi
  elif [ "$arch" = "x64" ]; then
    if [ "$TARGET_LINUX" == "1" ]; then
      local zipname="nano_linux_x64"
    else
      local zipname="nano_win64"
    fi
  else
    local zipname="nano_${arch}" # Default to just ${arch}
  fi
  local stage="${_builddir}/${zipname}"
  local zipfile="${zipname}.zip"

  if [ ! -f "${prefix}/bin/nano${fileext}" ]; then
    error_exit "packageNano: ${prefix}/bin/nano${fileext} not found"
  fi
  log "${GRE}Packaging nano for ${osname} ${arch}...${C0}\n"

  rm -rf "${stage}" "${OUT_DIR}/${zipfile}"
  mkdir -p "${stage}"
  cp -fv "${prefix}/bin/nano${fileext}" "${stage}/"
  # Ship our custom .nanorc (used automatically, since it sits beside nano)
  cp -fv "${HERE}/assets/nanorc" "${stage}/.nanorc"
  # Copy custom readme
  cp -fv "${HERE}/assets/readme.crlf" "${stage}/README.txt"

  # Zip from the arch dir so the archive holds a top-level ${zipname}/ folder
  # (nano_win32/ or nano_win64/), but write the .zip itself into out/.
  printf "${CYA} Zipping up ${BOLD}${stage}${C0}...\n"
  ( cd "${BUILD_DIR}/${arch}" && zip -r -q "${OUT_DIR}/${zipfile}" "${zipname}" ) \
    || error_exit "Failed to create ${zipfile}"
  rm -rf "${stage}"
  log "${GRE}Packaged ${BOLD}${OUT_DIR}/${zipfile}${C0}\n"
}

# Clone the vanilla nano source at NANO_VER into NANO_SRC (skip if already there).
fetch_nano() {
  if [ -e "${NANO_SRC}/configure.ac" ]; then
    log "${YEL}Reusing existing nano source at ${NANO_SRC}${C0}\n"
    return
  fi
  execute "Cloning nano ${NANO_VER}..." "Failed to clone nano from ${NANO_URL}" \
      git clone --depth 1 --branch "${NANO_VER}" "${NANO_URL}" "${NANO_SRC}"
}

# Download/extract ncurses source archive
fetch_ncurses() {
  if [ -x "${NCURSES_SRC}/configure" ]; then
    log "${YEL}Reusing existing ncurses source at ${NCURSES_SRC}${C0}\n"
    return
  fi
  cd "${SRC_DIR}"
  execute "Downloading ncurses ${NCURSES_VER}..." "Failed to download ncurses" \
  wget -c "${NCURSES_URL}"
  mkdir -p "${NCURSES_SRC}"
  execute "Extracting ncurses ${NCURSES_VER}..." "Failed to extract ncurses" \
  tar -xzf "${NCURSES_ARCHIVE}" -C "${NCURSES_SRC}" --strip-components=1
}

# Apply the per-OS patch series onto the vanilla nano source. The sentinel lives
# inside NANO_SRC (which is per-OS), so a fresh clone (or a wiped NANO_SRC) re-patches.
apply_patches() {
  if [ -f "${NANO_SRC}/.nano-patched" ]; then
    log "${BOLD}Already applied patches.${C0}\n"
    return
  fi
  # Windows NT4 compatibility (WINVER=0x0400 + dynamic AttachConsole) for the win
  # series, applied in series order. ncurses is a plain tarball (not a git repo)
  # nested inside this git repo, so `git apply` would find the parent repo and skip
  # every file -- use patch(1).
  log "${GRE}Patching ncurses...${C0}\n"
  apply_series "${HERE}/patches/ncurses" "${NCURSES_SRC}" patch
  log "${GRE}Patching nano...${C0}\n"
  # Apply every patch in patches/nano/ in series order (nano-win32 must be first).
  apply_series "${HERE}/patches/nano" "${NANO_SRC}" git
  # Drop in the app icon referenced by rc-icon.patch's windres rule (Windows only --
  # rc-icon isn't in the Linux series). nano.rc is created by that patch; the .ico
  # is binary, so it's copied here rather than embedded in a patch.
  if [ "$TARGET_LINUX" != "1" ]; then
    execute "Adding Windows resource icon..." "Failed to copy nano.ico" \
        cp -fv "${HERE}/assets/icon/nano.ico" "${NANO_SRC}/src/"
  fi
  # Report a clean release version. With roll-a-release.sh present, configure does
  # a "from git" build: it derives a dev-style version from the source tree and
  # requires the from-git pkg-config/gettext toolchain. Removing it makes configure
  # treat this as a release tarball, so nano reports "GNU nano, version 9.1".
  rm -f "${NANO_SRC}/roll-a-release.sh"
  touch "${NANO_SRC}/.nano-patched"
  log "${GRE}Done patching sources!${C0}\n"
}

clean_output() {
  printf "${YEL}Cleaning output directory...${C0}\n"
  rm -rf "${OUT_DIR}"/*.exe "${OUT_DIR}"/*.zip "${OUT_DIR}"/nano
  printf "${GRE}Done cleaning ${OUT_DIR} ${C0}\n"
}

clean_build() {
  printf "${YEL}Cleaning build directories...${C0}\n"
  rm -rf "${BUILD_DIR}"
  printf "${GRE}Done cleaning ${BUILD_DIR} ${C0}\n"
}

clean_sources() {
  printf "${YEL}Cleaning sources directory...${C0}\n"
  rm -rf "${SRC_DIR}/src" &&
  rm -rf "${SRC_DIR}/${NCURSES_ARCHIVE}"
  printf "${GRE}Done cleaning ${SRC_DIR} ${C0}\n"
}

# Main builder function
function buildNano() {
  local arch="$1"

  local _debug=""
  if [ "$IS_DEBUG" = true ]; then
    _debug="Debug"
  else
    _debug="Release"
  fi
  if [ "$arch" = "x86" ]; then
    local SIMD_FLAGS="-mfpmath=387 -mmmx -mno-sse -mno-sse2" # Plain x86 without SSE for old CPUs
    local march="i686"
  elif [ "$arch" = "x64" ]; then
    local SIMD_FLAGS="-mfpmath=sse -msse -mfxsr -msse2" # Plain x64 with SSE2
    local march="x86_64"
  else
    error_exit "Unsupported arch"
  fi
  if [ "$TARGET_LINUX" == "1" ]; then
    local osname="Linux"
    local fileext=""
    local _builddir="${BUILD_DIR}/linux_${arch}"
    local _host="$march-pc-linux-gnu" # Linux target triple    
  else
    local osname="Windows"
    local fileext=".exe"
    local _builddir="${BUILD_DIR}/win_${arch}"
    local _host="$march-w64-mingw32" # Windows target triple
  fi

  # Where make installs everything
  local _prefix="${_builddir}/install"

  if [ "$USE_LLVM" = true ]; then
    if [ "$TARGET_LINUX" == "1" ]; then
      local cc="clang"
      local cxx="clang++"
      local ld="clang++"
      local ar="ar"
      local rc=""
    else
      local cc="$march-w64-mingw32-clang"
      local cxx="$march-w64-mingw32-clang++"
      local ld="$march-w64-mingw32-clang++"
      local ar="$march-w64-mingw32-ar"
      local rc="$march-w64-mingw32-windres"
    fi
    # LLVM/MinGW links its runtime (compiler-rt/libc++) statically via -static in
    # LDFLAGS; the GCC-only -static-lib* flags would just warn "argument unused".
    local STATIC_LIBGCC="" STATIC_LIBSTDCXX=""
  else
    if [ "$TARGET_LINUX" == "1" ]; then
      local cc="gcc"
      local cxx="g++"
      local ld="g++"
      local ar="ar"
      local rc=""
    else
      local cc="$march-w64-mingw32-gcc"
      local cxx="$march-w64-mingw32-g++"
      local ld="$march-w64-mingw32-g++"
      local ar="$march-w64-mingw32-ar"
      local rc="$march-w64-mingw32-windres"
    fi
    local STATIC_LIBGCC="-static-libgcc" STATIC_LIBSTDCXX="-static-libstdc++"
  fi
  # Use our own compilers/linkers
  export CC="${cc}"
  export CXX="${cxx}"
  export LD="${ld}"
  export AR="${ar}"
  export RC="${rc}"

  if ! command -v "${cc}" >/dev/null 2>&1; then
    error_exit "${cc} not found on \$PATH; add your MinGW toolchain's bin/ dir to PATH first."
  fi

  log "${GRE}Building Nano for ${osname} ${arch} (${_debug}) ${C0}\n"

  # Optimization and debug/release flags. Debug builds also keep symbols by
  # installing with plain `make install` instead of `install-strip`.
  local OPT_FLAGS="-Wno-error ${SIMD_FLAGS}"
  if [ "$IS_DEBUG" = true ]; then
    OPT_FLAGS+=" -Og -g2 -DDEBUG -D_DEBUG"
    local STRIP_FLAG=""
    local INSTALL_TARGET="install"
  else
    OPT_FLAGS+=" -O3 -g0 -DNDEBUG -D_NDEBUG"
    local STRIP_FLAG="-s"
    local INSTALL_TARGET="install-strip"
  fi
  local MFLAG=""
  if [ "$TARGET_LINUX" == "1" ]; then
    if [ "$arch" = "x86" ]; then
      MFLAG+="-m32"
    elif [ "$arch" = "x64" ]; then
      MFLAG+="-m64"
    fi
  fi
  # Targeting defines and the PE console-subsystem link flag are Windows-only. On
  # Linux the defines are just meaningless, but -Wl,--subsystem is PE-only and makes
  # ld fail there ("unrecognized option '--subsystem'"), so gate both on the target.
  # (Only set _WIN32_WINNT; WINVER is derived from it by sdkddkver.h. Defining WINVER
  # explicitly collides with ncurses' win32 driver's own -DWINVER (now 0x0400).)
  if [ "$TARGET_LINUX" == "1" ]; then
    local DEFINES="-DUNICODE -D_UNICODE"
    local SUBSYS=""
    # Build a static position-independent executable (ASLR). -static + -pie do NOT
    # combine (-static wins, giving a non-PIE binary), so use the single -static-pie
    # flag. Needs a glibc with static-pie support (fine on modern distros/Ubuntu 22.04+).
    local PIE_CFLAGS="-fPIE"
    local STATIC_LINK="-static-pie"
  else
    local DEFINES="-D__USE_MINGW_ANSI_STDIO -D_CONSOLE -DUNICODE -D_UNICODE -D_WIN32_WINNT=$WIN32_WINNT"
    local SUBSYS="-Wl,--subsystem,console:4.00"
    # PE relocation differs from ELF PIE and the legacy Windows targets (pre-Vista)
    # have no ASLR, so keep the executable non-PIE and plain -static.
    local PIE_CFLAGS=""
    local STATIC_LINK="-static"
  fi
  # NOTE: do NOT add -municode -- this toolchain's unicode startup pulls in a
  # wWinMain reference, but nano only defines main(), so any -municode (in CFLAGS or
  # LDFLAGS) breaks the link with "undefined reference to wWinMain".
  export CFLAGS="${OPT_FLAGS} ${DEFINES} ${MFLAG} ${PIE_CFLAGS} ${STATIC_LIBGCC} -pipe"
  export CPPFLAGS="${OPT_FLAGS} ${DEFINES} ${MFLAG} ${PIE_CFLAGS} ${STATIC_LIBSTDCXX} -I${_prefix}/include -pipe"
  export CXXFLAGS="${CPPFLAGS}"
  export LDFLAGS="-L${_prefix}/lib ${STATIC_LINK} ${STRIP_FLAG} ${SUBSYS}"
  # Libraries to link
  if [ "$TARGET_LINUX" == "1" ]; then
    export LIBS="-lm"
  else
    export LIBS="-lkernel32 -lshlwapi"
  fi

  export PKG_CONFIG=true # Bypass pkg-config; use the manual NCURSESW_* flags below
  # Link in static ncurses
  export NCURSESW_CFLAGS="-I${_prefix}/include/ncursesw -DNCURSES_STATIC"
  export NCURSESW_LIBS="-lncursesw"

  # Verbose build flags
  if [ "$VERBOSE" == "1" ]; then
    local VFLAGS="VERBOSE=1 V=1"
    local QUIETFLAG="--disable-silent-rules"
  else
    local VFLAGS=""
    local QUIETFLAG="--quiet"
  fi

  # Log final build flags and pause so user can read it
  log "${CYA}CFLAGS   ${C0}= ${BOLD}${CFLAGS} ${NCURSESW_CFLAGS} ${C0}\n"
  log "${CYA}CXXFLAGS ${C0}= ${BOLD}${CXXFLAGS} ${C0}\n"
  log "${CYA}LDFLAGS  ${C0}= ${BOLD}${LDFLAGS} ${C0}\n"
  log "${CYA}LIBS     ${C0}= ${BOLD}${LIBS} ${NCURSESW_LIBS} ${C0}\n"
  sleep 1

  # Host triple
  local _build="$(gcc -dumpmachine)"
  # Make per-arch build dir and switch to it
  mkdir -p "${_builddir}"
  cd "${_builddir}"

  # Per-arch build log so a second arch's build doesn't clobber the first one's.
  # `local` here shadows the global LOG_FILE via dynamic scoping, so execute()
  # calls made from this function write here; the fetch/patch phase keeps using
  # the shared ${BUILD_DIR}/build.log.
  local LOG_FILE="${_builddir}/build_${arch}.log"
  : > "${LOG_FILE}"

  local NCURSES_FEATURES="--enable-widec --enable-sp-funcs --enable-termcap --enable-term-driver --enable-interop"
  if [ "$IS_DEBUG" = true ]; then
    NCURSES_FEATURES+=" --with-debug"
  else
    NCURSES_FEATURES+=" --without-debug"
  fi
  # Windows uses the built-in win32 console driver: no terminfo, no programs. Linux
  # reads the system terminfo database (so every installed terminal works), keeps
  # compiled-in fallbacks as a backstop for hosts that lack one, and builds the
  # tic/infocmp those fallbacks need (rather than depending on the host's ncurses-bin).
  if [ "$TARGET_LINUX" == "1" ]; then
    NCURSES_FEATURES+=" --with-fallbacks=linux,vt100,vt220,xterm,xterm-256color,screen,tmux,tmux-256color,rxvt,ansi,dumb"
    NCURSES_FEATURES+=" --with-terminfo-dirs=/usr/share/terminfo:/lib/terminfo:/etc/terminfo"
  else
    NCURSES_FEATURES+=" --without-progs --disable-database --disable-home-terminfo"
  fi

  # Build/install ncurses (out-of-tree against the extracted source; absolute
  # source path so it works regardless of this build dir's depth)
  mkdir -p "ncurses" && cd "ncurses"
  printf "${CYA}Configuring ncurses with ${BOLD}${NCURSES_FEATURES} ${C0}\n"
  execute "" "Failed to configure ncurses!" \
  "${NCURSES_SRC}/configure"  \
    --build="${_build}" --host="${_host}" --prefix="${_prefix}"  \
    --disable-dependency-tracking  \
    $NCURSES_FEATURES \
    --disable-{shared,rpath,db-install,getcap}  \
    --without-{ada,cxx-binding,manpages,pthread,tests,libtool} \
    $QUIETFLAG
  execute "Building ncurses..." "ncurses build failed." \
  make -j $JOBS $VFLAGS
  execute "Installing ncurses..." "ncurses install failed." \
  make install $VFLAGS
  cd ..

  # Nano feature set: a normal build enables color/utf8/nanorc; --tiny makes a
  # minimal build via --enable-tiny (which also drops this fork's enhancements,
  # since they live under the NANO_TINY/ENABLE_* guards).
  # Always enable these
  local NANO_FEATURES="--enable-utf8 --enable-nanorc --enable-linenumbers --enable-wrapping --enable-operatingdir"
  if [ "$IS_TINY" = true ]; then
    NANO_FEATURES+=" --enable-tiny" # Tiny build + some enhancements
  else
    NANO_FEATURES+=" --enable-color --enable-help --enable-mouse --enable-browser --enable-extra"
  fi
  if [ "$IS_DEBUG" = true ]; then
    NANO_FEATURES+=" --enable-debug"
  fi

  # Build nano itself (out-of-tree against the cloned+patched source in NANO_SRC)
  mkdir -p "nano" && cd "nano"
  printf "${CYA}Configuring nano with ${BOLD}${NANO_FEATURES} ${C0}\n"
  execute "" "Failed to configure nano!" \
  "${NANO_SRC}/configure"  \
    --build="${_build}" --host="${_host}" --prefix="${_prefix}"  \
    --disable-dependency-tracking  \
    $NANO_FEATURES \
    --disable-{nls,speller,threads,rpath,libmagic} \
    $QUIETFLAG
  execute "Building nano..." "nano build failed." \
  make -j $JOBS $VFLAGS
  execute "Installing nano..." "nano install failed." \
  make ${INSTALL_TARGET} $VFLAGS # release: install-strip; debug: plain install
  cd "$HERE"

  # copy bare executable deliverable
  cp -fv "${_prefix}/bin/nano${fileext}" "${OUT_DIR}/nano-${arch}${fileext}"

  log "${GRE}Done building Nano for ${osname} ${arch} (${_debug}) ${C0}\n"

  # Optionally zip the result into out/nano_<os>.zip
  if [ "$PACKAGE" ]; then
    packageNano "$arch" "$_prefix"
  fi
}

# Cmdline handling
while :; do
  case $1 in
    -h|--help)
        show_help
        exit 0
        ;;
    --version)
        show_version
        ;;
    --deps)
        install_deps
        exit 0
        ;;
    -v|--verbose)
        VERBOSE=1
        ;;
    -d|--debug)
        IS_DEBUG=true
        ;;
    -t|--tiny)
        IS_TINY=true
        ;;
    --distclean)
        clean_build
        clean_output
        exit 0
        ;;
    --srcclean)
        clean_build
        clean_sources
        exit 0
        ;;
    -c|--clean)
        clean_build
        clean_output
        clean_sources
        exit 0
        ;;
    -j|--jobs)
        if [ "$2" ]; then
          JOBS=$2
          shift
        else
          arg_error "'--jobs' requires a non-empty option argument"
        fi
        ;;
    i686|x32|x86|32|-32|--32)
        BUILD_I686=1
        ;;
    x86_64|x64|amd64|64|-64|--64)
        BUILD_X86_64=1
        ;;
    -p|--package)
        PACKAGE=1
        ;;
    --patch)
        PATCH_ONLY=1
        ;;
    -l|--llvm)
        USE_LLVM=true
        ;;
    --linux)
        TARGET_LINUX=1
        ;;
    --)
        shift
        break
        ;;
    -?*)
        arg_error "Unknown option '$1'"
        ;;
    ?*)
        arg_error "Unknown architecture '$1'"
        ;;
    *)
        break
  esac

  shift
done

# An architecture is required unless we are only fetching + patching (--patch).
if [ ! "$PATCH_ONLY" ] && [ ! "$BUILD_I686" ] && [ ! "$BUILD_X86_64" ]; then
  arg_error "No architecture specified (i686/x32 and/or x86_64/x64)"
fi

if [ "$PACKAGE" ] && ! command -v zip >/dev/null 2>&1; then
  error_exit "--package requires 'zip'; run '$SCRIPTNAME --deps' or install it manually"
fi

# Everything is fetched/built under $HERE regardless of the caller's cwd.
cd "${HERE}"

# Per-OS source trees: Windows and Linux get different patch series, so keep their
# fetched+patched sources separate. This lets you switch targets without a clean.
if [ "$TARGET_LINUX" == "1" ]; then
  NANO_SRC="${SRC_DIR}/src/nano-linux"
  NCURSES_SRC="${SRC_DIR}/src/ncurses-linux"
fi

printf "${BOLD}Nano build script ver. ${ULINE}${SCRIPTVER}${C0}\n"

mkdir -p "${OUT_DIR}"
mkdir -p "${SRC_DIR}"
mkdir -p "${BUILD_DIR}"
# start a fresh build log (execute() appends to it)
: > "${LOG_FILE}"

# Fetch ncurses, then fetch vanilla nano and layer the Windows patches on top.
fetch_ncurses
fetch_nano
apply_patches
rm -rf "${SRC_DIR}/${NCURSES_ARCHIVE}" # Cleanup ncurses tarball now

# --patch: stop with the sources fetched and patched, but not configured or built.
if [ "$PATCH_ONLY" ]; then
  log "${GRE}Sources fetched and patched (--patch); skipping configure/build.${C0}\n"
  log "  ${BOLD}nano:${C0}    ${NANO_SRC}\n"
  log "  ${BOLD}ncurses:${C0} ${NCURSES_SRC}\n"
  exit 0
fi

# Generate configure & the gnulib import in the source tree (needed since we
# build "from git").
if [ ! -x "${NANO_SRC}/configure" ]; then
  execute "Running autogen.sh..." "autogen.sh failed" \
      sh -c 'cd "$1" && ./autogen.sh' _ "${NANO_SRC}"
fi

# Build 32 bit nano
if [ "$BUILD_I686" ]; then
  buildNano x86
fi
# Build 64 bit nano
if [ "$BUILD_X86_64" ]; then
  buildNano x64
fi
