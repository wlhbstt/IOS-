#!/usr/bin/env bash
set -euo pipefail

toolchain_dir="${PHOTO_CLEANER_SWIFT_DIR:-$HOME/.cache/photo-cleaner-swift}"
swift_bin="$toolchain_dir/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swift"
mkdir -p "$toolchain_dir/deps"
if [ ! -x "$swift_bin" ]; then
    curl -fL --retry 2 -o "$toolchain_dir/toolchain.tar.gz" \
        https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu24.04.tar.gz
    tar -xzf "$toolchain_dir/toolchain.tar.gz" -C "$toolchain_dir"
fi
if [ ! -f "$toolchain_dir/deps/usr/lib/x86_64-linux-gnu/libncurses.so.6" ] && \
   [ ! -f "$toolchain_dir/deps/lib/x86_64-linux-gnu/libncurses.so.6" ]; then
    (
        cd "$toolchain_dir/deps"
        apt-get download libncurses6
        dpkg-deb -x libncurses6*.deb .
    )
fi
export LD_LIBRARY_PATH="$toolchain_dir/deps/lib/x86_64-linux-gnu:$toolchain_dir/deps/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export PATH="$(dirname "$swift_bin"):$PATH"
exec "$swift_bin" "$@"
