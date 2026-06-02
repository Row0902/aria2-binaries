#!/usr/bin/env bash
# Build aria2 statically for Android (aarch64, armv7, x86_64)
#
# Usage: ./build-android.sh <target>
#   target: aarch64 | armv7 | x86_64
#
# Prerequisites:
#   - Android NDK (set ANDROID_NDK_HOME or use setup-ndk action)
#   - autoconf, automake, libtool, pkg-config
#
# Dependencies built from source:
#   - OpenSSL 1.1.1w
#   - expat 2.5.0
#   - zlib 1.3.1
#   - c-ares 1.21.0
#
# Based on upstream Dockerfile.android

set -euo pipefail

TARGET="${1:-aarch64}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/aria2-android-build"
INSTALL_DIR="$WORK_DIR/usr/local"
SRC_DIR="$WORK_DIR/src"

# Map friendly names to NDK triples and OpenSSL targets
case "$TARGET" in
  aarch64)
    NDK_TRIPLE="aarch64-linux-android"
    OPENSSL_TARGET="android-arm64"
    BINARY="aria2c-android-aarch64"
    ;;
  armv7)
    NDK_TRIPLE="armv7a-linux-androideabi"
    OPENSSL_TARGET="android-arm"
    BINARY="aria2c-android-armv7"
    # configure --host uses arm-linux-androideabi for armv7
    CONFIG_HOST="arm-linux-androideabi"
    ;;
  x86_64)
    NDK_TRIPLE="x86_64-linux-android"
    OPENSSL_TARGET="android-x86_64"
    BINARY="aria2c-android-x86_64"
    ;;
  *)
    echo "Usage: $0 {aarch64|armv7|x86_64}"
    exit 1
    ;;
esac

# Allow overriding the config host for armv7 special case
CONFIG_HOST="${CONFIG_HOST:-$NDK_TRIPLE}"

API="${ANDROID_API:-24}"
JOBS="${JOBS:-$(nproc)}"

# Library versions (matching upstream Dockerfile.android)
OPENSSL_VERSION="${OPENSSL_VERSION:-3.4.5}"
LIBEXPAT_VERSION="${LIBEXPAT_VERSION:-2.8.1}"
ZLIB_VERSION="${ZLIB_VERSION:-1.3.2}"
CARES_VERSION="${CARES_VERSION:-1.34.6}"

echo "=========================================="
echo " Building aria2 for Android - $TARGET"
echo " NDK triple: $NDK_TRIPLE"
echo " Config host: $CONFIG_HOST"
echo " API level: $API"
echo " Jobs: $JOBS"
echo "=========================================="

# --- Check prerequisites ---
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  echo "ERROR: ANDROID_NDK_HOME is not set"
  exit 1
fi

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
if [ ! -d "$TOOLCHAIN" ]; then
  echo "ERROR: NDK toolchain not found at $TOOLCHAIN"
  exit 1
fi

export CC="$TOOLCHAIN/bin/${NDK_TRIPLE}${API}-clang"
export CXX="$TOOLCHAIN/bin/${NDK_TRIPLE}${API}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export LD="$TOOLCHAIN/bin/ld"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export PKG_CONFIG_LIBDIR="$INSTALL_DIR/lib/pkgconfig"
export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig"

# --- Clean and prepare ---
rm -rf "$WORK_DIR"
mkdir -p "$SRC_DIR" "$INSTALL_DIR"

# Save original directory (aria2 source)
ARIA2_SRC_DIR="$(pwd)"

# Verify we're in the aria2 source tree
if [ ! -f "$ARIA2_SRC_DIR/configure.ac" ]; then
  echo "ERROR: Run this script from the aria2 source root directory"
  exit 1
fi

# Run autoreconf if needed
if [ ! -f "$ARIA2_SRC_DIR/configure" ]; then
  echo ">>> Running autoreconf -i"
  autoreconf -i
fi

# ============================================
# Build OpenSSL
# ============================================
echo ""
echo ">>> Building OpenSSL $OPENSSL_VERSION"
cd "$SRC_DIR"
if [ ! -f "openssl-$OPENSSL_VERSION.tar.gz" ]; then
  curl -fSL -o "openssl-$OPENSSL_VERSION.tar.gz" \
    "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"
fi
tar xf "openssl-$OPENSSL_VERSION.tar.gz"
cd "openssl-$OPENSSL_VERSION"

# OpenSSL Configure uses different env vars
export ANDROID_NDK_HOME
# NDK r29+ only has clang (no gcc). OpenSSL's 15-android.conf
# finds the NDK toolchain via PATH when ANDROID_NDK_HOME is set.
export PATH="$TOOLCHAIN/bin:$PATH"

./Configure \
  no-shared \
  no-asm \
  no-tests \
  --prefix="$INSTALL_DIR" \
  "$OPENSSL_TARGET" \
  -D__ANDROID_API__="$API"

make -j"$JOBS" build_libs
make install_sw
unset ANDROID_NDK_HOME
cd "$SRC_DIR"

# ============================================
# Build expat
# ============================================
echo ""
echo ">>> Building expat $LIBEXPAT_VERSION"
cd "$SRC_DIR"
if [ ! -f "expat-$LIBEXPAT_VERSION.tar.bz2" ]; then
  curl -fSL -o "expat-$LIBEXPAT_VERSION.tar.bz2" \
    "https://github.com/libexpat/libexpat/releases/download/R_$(echo $LIBEXPAT_VERSION | tr . _)/expat-$LIBEXPAT_VERSION.tar.bz2"
fi
tar xf "expat-$LIBEXPAT_VERSION.tar.bz2"
cd "expat-$LIBEXPAT_VERSION"

./configure \
  --host="$CONFIG_HOST" \
  --build="$(dpkg-architecture -qDEB_BUILD_GNU_TYPE)" \
  --prefix="$INSTALL_DIR" \
  --disable-shared \
  --without-docbook \
  --without-examples \
  --without-tests

make -j"$JOBS" install
cd "$SRC_DIR"

# ============================================
# Build zlib
# ============================================
echo ""
echo ">>> Building zlib $ZLIB_VERSION"
cd "$SRC_DIR"
if [ ! -f "zlib-$ZLIB_VERSION.tar.gz" ]; then
  curl -fSL -o "zlib-$ZLIB_VERSION.tar.gz" \
    "https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz"
fi
tar xf "zlib-$ZLIB_VERSION.tar.gz"
cd "zlib-$ZLIB_VERSION"

./configure \
  --prefix="$INSTALL_DIR" \
  --libdir="$INSTALL_DIR/lib" \
  --includedir="$INSTALL_DIR/include" \
  --static

make -j"$JOBS" install
cd "$SRC_DIR"

# ============================================
# Build c-ares
# ============================================
echo ""
echo ">>> Building c-ares $CARES_VERSION"
cd "$SRC_DIR"
if [ ! -f "c-ares-$CARES_VERSION.tar.gz" ]; then
  curl -fSL -o "c-ares-$CARES_VERSION.tar.gz" \
    "https://github.com/c-ares/c-ares/releases/download/v$CARES_VERSION/c-ares-$CARES_VERSION.tar.gz"
fi
tar xf "c-ares-$CARES_VERSION.tar.gz"
cd "c-ares-$CARES_VERSION"

./configure \
  --host="$CONFIG_HOST" \
  --build="$(dpkg-architecture -qDEB_BUILD_GNU_TYPE)" \
  --prefix="$INSTALL_DIR" \
  --disable-shared

make -j"$JOBS" install
cd "$SRC_DIR"

# ============================================
# Build aria2
# ============================================
echo ""
echo ">>> Building aria2"
cd "$ARIA2_SRC_DIR"

if [ "$TARGET" = "armv7" ]; then
  # For armv7 we need to use the correct host triple for configure
  CONFIGURE_HOST="arm-linux-androideabi"
else
  CONFIGURE_HOST="$NDK_TRIPLE"
fi

./configure \
  ARIA2_STATIC=yes \
  --prefix="$WORK_DIR/aria2-install" \
  --host="$CONFIGURE_HOST" \
  --build="$(dpkg-architecture -qDEB_BUILD_GNU_TYPE)" \
  --disable-nls \
  --without-gnutls \
  --with-openssl \
  --without-sqlite3 \
  --without-libxml2 \
  --with-libexpat \
  --with-libcares \
  --with-libz \
  --without-libssh2 \
  CPPFLAGS="-fPIE -I$INSTALL_DIR/include" \
  CFLAGS="-Os -g" \
  CXXFLAGS="-Os -g" \
  LDFLAGS="-fPIE -pie -L$INSTALL_DIR/lib -static-libstdc++"

make -j"$JOBS" V=1
make install-strip

# ============================================
# Package
# ============================================
echo ""
echo ">>> Packaging binary"
mkdir -p dist
cp "$WORK_DIR/aria2-install/bin/aria2c" "dist/$BINARY"
"$STRIP" "dist/$BINARY"
chmod +x "dist/$BINARY"

echo ""
echo "=========================================="
echo " Build complete: dist/$BINARY"
ls -lh "dist/$BINARY"
echo "=========================================="
