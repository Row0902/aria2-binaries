#!/usr/bin/env bash
# Build static dependencies for aria2 on Linux (native and cross-compile)
#
# Usage: ./build-deps-linux.sh <target> <prefix>
#   target: x86_64 | aarch64 | armv7
#   prefix: install prefix (default: /tmp/aria2-deps)
#
# For x86_64 (native): builds only c-ares (the only dep missing static .a on Noble)
# For aarch64/armv7 (cross): builds all deps from source because Ubuntu 24.04
#   no longer provides :arm64/:armhf multiarch packages.
#
# Output: exports PKG_CONFIG_PATH pointing to the built deps

set -euo pipefail

TARGET="${1:-x86_64}"
PREFIX="${2:-/tmp/aria2-deps}"
JOBS="${JOBS:-$(nproc)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$PREFIX-build"
SRC_DIR="$WORK_DIR/src"
INSTALL_DIR="$PREFIX"

# Library versions (matching build-android.sh where applicable)
OPENSSL_VERSION="${OPENSSL_VERSION:-3.4.5}"
LIBEXPAT_VERSION="${LIBEXPAT_VERSION:-2.8.1}"
ZLIB_VERSION="${ZLIB_VERSION:-1.3.2}"
CARES_VERSION="${CARES_VERSION:-1.34.6}"
SQLITE_VERSION="${SQLITE_VERSION:-3490100}"  # 3.49.1
LIBSSH2_VERSION="${LIBSSH2_VERSION:-1.11.1}"
LIBGPG_ERROR_VERSION="${LIBGPG_ERROR_VERSION:-1.51}"
LIBXML2_VERSION="${LIBXML2_VERSION:-2.14.2}"
LZMA_VERSION="${LZMA_VERSION:-5.8.3}"  # xz/utils

# Map target → host triple
case "$TARGET" in
  x86_64)
    CONFIGURE_HOST=""
    ;;
  aarch64)
    CONFIGURE_HOST="aarch64-linux-gnu"
    ;;
  armv7)
    CONFIGURE_HOST="arm-linux-gnueabihf"
    ;;
  *)
    echo "Usage: $0 {x86_64|aarch64|armv7} [prefix]"
    exit 1
    ;;
esac

# Cross-compilation flags
if [ -n "$CONFIGURE_HOST" ]; then
  CROSS_PREFIX="${CONFIGURE_HOST}-"
  CC="${CROSS_PREFIX}gcc"
  CXX="${CROSS_PREFIX}g++"
  AR="${CROSS_PREFIX}ar"
  RANLIB="${CROSS_PREFIX}ranlib"
  STRIP="${CROSS_PREFIX}strip"
else
  CROSS_PREFIX=""
  CC="gcc"
  CXX="g++"
  AR="ar"
  RANLIB="ranlib"
  STRIP="strip"
fi

export CC CXX AR RANLIB STRIP

echo "=========================================="
echo " Building deps for Linux - $TARGET"
echo " Host: ${CONFIGURE_HOST:-native}"
echo " Prefix: $INSTALL_DIR"
echo " Jobs: $JOBS"
echo "=========================================="

# Clean and prepare
rm -rf "$WORK_DIR"
mkdir -p "$SRC_DIR" "$INSTALL_DIR"

export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$INSTALL_DIR/lib/pkgconfig"
export CPATH="$INSTALL_DIR/include"
export LIBRARY_PATH="$INSTALL_DIR/lib"

# Helper: download and extract
fetch_and_extract() {
  local name="$1" url="$2"
  local filename="${3:-}"
  if [ -z "$filename" ]; then
    filename="$(basename "$url")"
  fi
  cd "$SRC_DIR"
  if [ ! -f "$filename" ]; then
    echo ">>> Downloading $name"
    curl -fSL -o "$filename" "$url"
  fi
  echo ">>> Extracting $name"
  tar xf "$filename"
}

# Helper: generic autotools build
build_autotools() {
  local name="$1" dir="$2"
  shift 2
  cd "$SRC_DIR/$dir"
  echo ">>> Configuring $name"
  # Determine build triple: dpkg-architecture returns the full triple,
  # uname -m needs -linux-gnu appended.
  BUILD_TRIPLE="$(dpkg-architecture -qDEB_BUILD_GNU_TYPE 2>/dev/null || echo "$(uname -m)-linux-gnu")"
  ./configure \
    --host="$CONFIGURE_HOST" \
    --build="$BUILD_TRIPLE" \
    --prefix="$INSTALL_DIR" \
    --disable-shared \
    --enable-static \
    "$@"
  echo ">>> Building $name"
  make -j"$JOBS" install
}

# ============================================
# Build c-ares (needed for ALL targets)
# ============================================
build_cares() {
  fetch_and_extract "c-ares" \
    "https://github.com/c-ares/c-ares/releases/download/v${CARES_VERSION}/c-ares-${CARES_VERSION}.tar.gz"

  cd "$SRC_DIR/c-ares-$CARES_VERSION"

  echo ">>> Configuring c-ares"
  BUILD_TRIPLE="$(dpkg-architecture -qDEB_BUILD_GNU_TYPE 2>/dev/null || echo "$(uname -m)-linux-gnu")"
  ./configure \
    --host="$CONFIGURE_HOST" \
    --build="$BUILD_TRIPLE" \
    --prefix="$INSTALL_DIR" \
    --disable-shared \
    --enable-static \
    --disable-tests \
    --disable-debug

  echo ">>> Building c-ares"
  make -j"$JOBS" install
  echo ">>> c-ares built OK"
}

# ============================================
# Build zlib (cross-compile only)
# ============================================
build_zlib() {
  fetch_and_extract "zlib" \
    "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz"

  cd "$SRC_DIR/zlib-$ZLIB_VERSION"

  echo ">>> Configuring zlib"
  ./configure \
    --prefix="$INSTALL_DIR" \
    --libdir="$INSTALL_DIR/lib" \
    --includedir="$INSTALL_DIR/include" \
    --static

  echo ">>> Building zlib"
  make -j"$JOBS" install
  echo ">>> zlib built OK"
}

# ============================================
# Build OpenSSL (cross-compile only)
# ============================================
build_openssl() {
  fetch_and_extract "OpenSSL" \
    "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"

  cd "$SRC_DIR/openssl-$OPENSSL_VERSION"

  # Map target to OpenSSL target
  local openssl_target
  case "$TARGET" in
    aarch64) openssl_target="linux-aarch64" ;;
    armv7)   openssl_target="linux-armv4" ;;
    *)       openssl_target="linux-x86_64" ;;
  esac

  echo ">>> Configuring OpenSSL"
  ./Configure \
    no-shared \
    no-asm \
    no-tests \
    --prefix="$INSTALL_DIR" \
    "$openssl_target" \
    -fPIC

  echo ">>> Building OpenSSL"
  make -j"$JOBS" build_libs
  make install_sw
  echo ">>> OpenSSL built OK"
}

# ============================================
# Build expat (cross-compile only)
# ============================================
build_expat() {
  fetch_and_extract "expat" \
    "https://github.com/libexpat/libexpat/releases/download/R_$(echo $LIBEXPAT_VERSION | tr . _)/expat-${LIBEXPAT_VERSION}.tar.bz2"

  build_autotools "expat" "expat-$LIBEXPAT_VERSION" \
    --without-docbook \
    --without-examples \
    --without-tests \
    --without-xmlwf
}

# ============================================
# Build sqlite3 (cross-compile only)
# ============================================
build_sqlite3() {
  fetch_and_extract "sqlite3" \
    "https://www.sqlite.org/2025/sqlite-autoconf-${SQLITE_VERSION}.tar.gz"

  build_autotools "sqlite3" "sqlite-autoconf-$SQLITE_VERSION"
}

# ============================================
# Build libssh2 (cross-compile only)
# ============================================
build_libssh2() {
  fetch_and_extract "libssh2" \
    "https://github.com/libssh2/libssh2/releases/download/libssh2-${LIBSSH2_VERSION}/libssh2-${LIBSSH2_VERSION}.tar.gz"

  build_autotools "libssh2" "libssh2-$LIBSSH2_VERSION" \
    --with-libssl-prefix="$INSTALL_DIR" \
    --disable-examples-build \
    --disable-crypto-engine
}

# ============================================
# Build libgpg-error (cross-compile only)
# ============================================
build_libgpg_error() {
  fetch_and_extract "libgpg-error" \
    "https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-${LIBGPG_ERROR_VERSION}.tar.bz2"

  cd "$SRC_DIR/libgpg-error-$LIBGPG_ERROR_VERSION"

  # Need to run autoreconf for cross-compile on newer autotools
  if [ -n "$CONFIGURE_HOST" ]; then
    autoreconf -fi 2>/dev/null || true
  fi

  build_autotools "libgpg-error" "libgpg-error-$LIBGPG_ERROR_VERSION" \
    --disable-nls \
    --disable-languages
}

# ============================================
# Build libxml2 (cross-compile only)
# ============================================
build_libxml2() {
  fetch_and_extract "libxml2" \
    "https://download.gnome.org/sources/libxml2/$(echo $LIBXML2_VERSION | cut -d. -f1-2)/libxml2-${LIBXML2_VERSION}.tar.xz"

  build_autotools "libxml2" "libxml2-$LIBXML2_VERSION" \
    --without-python \
    --without-lzma \
    --disable-maintainer-mode
}

# ============================================
# Main build logic
# ============================================

# c-ares: needed for all targets
build_cares

if [ -n "$CONFIGURE_HOST" ]; then
  # Cross-compile: build everything from source
  echo ""
  echo "=== Cross-compile mode: building all deps from source ==="

  build_zlib
  build_openssl
  build_expat
  build_sqlite3
  build_libssh2
  build_libgpg_error
  build_libxml2
  # lzma/xz: from system package for now
else
  # Native: only c-ares needs from-source build
  echo ""
  echo "=== Native mode: c-ares built from source ==="
fi

echo ""
echo "=========================================="
echo " Dependencies built successfully"
echo " Target: $TARGET"
echo " PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
echo "=========================================="

# Output the PKG_CONFIG_PATH for use in CI
echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
