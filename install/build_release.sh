#!/bin/bash

source "$(dirname "$BASH_SOURCE")/build_env.sh" || exit 1

build_32bit=false
build_psol=true
build_stable=

options="$(getopt --long 32bit,skip_psol,stable -o '' -- "$@")"
eval set -- "$options"

while [ $# -gt 0 ]; do
  case "$1" in
    --32bit) build_32bit=true; shift ;;
    --skip_psol) build_psol=false; shift ;;
    --stable) build_stable=--stable_package; shift ;;
    --) shift; break ;;
    *) echo "getopt error" >&2; exit 1 ;;
  esac
done

if [ $# -ne 0 ]; then
  echo "Usage: $(basename $0) [--32bit] [--stable] [--skip_psol]" >&2
  exit 1
fi

host_is_32bit=true
if [ "$(uname -m)" = x86_64 ]; then
  host_is_32bit=false
fi

if $host_is_32bit && ! $build_32bit; then
  echo "This builds 64-bit binaries by default, but your host is 32-bit" >&2
  echo "If you want a 32-bit binary, try again with --32_bit" >&2
  exit 1
fi

source net/instaweb/public/VERSION
build_version="$MAJOR.$MINOR.$BUILD.$PATCH"

release_dir="$HOME/release/${build_version}"
if $build_32bit; then
  release_dir="$release_dir/ia32"
else
  release_dir="$release_dir/x64"
fi

rm -rf "$release_dir"

# Setup chroot if we need it.

run_in_chroot=
if $build_32bit && ! $host_is_32bit; then
  run_in_chroot=install/run_in_chroot.sh
  sudo install/setup_chroot.sh
fi

# Run the various build scripts.

sudo $run_in_chroot \
  install/install_required_packages.sh --additional_test_packages
$run_in_chroot install/build_mps.sh --build_$PKG_EXTENSION $build_stable
sudo $run_in_chroot \
  install/test_package.sh out/Release/mod-pagespeed*.$PKG_EXTENSION

if $build_psol; then
  $run_in_chroot install/build_psol.sh
fi

# Builds all complete, now copy release artifacts into $release_dir.

mkdir -p "$release_dir"
cp out/Release/mod-pagespeed*.$PKG_EXTENSION "$release_dir/"

nbits=64
if $build_32bit; then
  nbits=32
fi

for f in libmod_pagespeed.so libmod_pagespeed_ap24.so; do
  cp "out/Release/$f" \
    "$release_dir/unstripped_libmodpagespeed_${nbits}_${PKG_EXTENSION}.so"
done

if $build_psol; then
  cp psol-*.tar.gz "$release_dir/"
fi

echo "Build complete"
