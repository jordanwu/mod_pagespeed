#!/bin/bash

set -e  # exit script if any command returns an error
set -u  # exit the script if any variable is uninitialized

eval set -- "$(getopt --long build_deb,build_rpm,debug -- $@)"

BUILDTYPE=Release
PACKAGE_TARGET=
CHANNEL=beta ## FIXME

while [ $# -gt 0 ]; do
  case "$1" in
    --debug) BUILDTYPE=Debug; shift ;;
    --build_deb) PACKAGE_TARGET=linux_package_deb; shift ;;
    --build_rpm) PACKAGE_TARGET=linux_package_rpm; shift ;;
    --) shift; break ;;
    *) echo "getopt error" >&2; exit 1 ;;
  esac
done

## FIXME - rm src/build/wrappers/ar.sh
## FIXME - rm src/install/ubuntu.sh, centos.sh, opensuse.sh
MAKE_ARGS="BUILDTYPE=$BUILDTYPE V=1"

# Are we on CentOS or Ubuntu?
if grep -q CentOS /etc/issue; then
  echo We appear to be running on CentOS.

  RESTART="./centos.sh apache_debug_restart"
  TEST="./centos.sh enable_ports_and_file_access apache_vm_system_tests"
  COMPILER_BIN=/opt/rh/devtoolset-2/root/usr/bin/

  export SSL_CERT_DIR=/etc/pki/tls/certs
  export SSL_CERT_FILE=/etc/pki/tls/cert.pem

  # MANYLINUX1 is required for CentOS 5 (but probably not newer CentOS).
  export CFLAGS='-DGPR_MANYLINUX1 -std=gnu99'
else
  echo We appear to NOT be running on CentOS.

  RESTART="./ubuntu.sh apache_debug_restart"
  TEST="./ubuntu.sh apache_vm_system_tests"
  COMPILER_BIN=/usr/lib/gcc-mozilla/bin/
fi

rm -rf log
mkdir -p log

if [ -d depot_tools ]; then
  (cd depot_tools && git pull)
else
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi

PATH=$PWD/depot_tools:$PATH
if [ -d "$COMPILER_BIN" ]; then
  PATH="$COMPILER_BIN:$PATH"
fi

run_with_log log/gclient.log \
    gclient config https://github.com/pagespeed/mod_pagespeed.git --unmanaged --name=$PWD
run_with_log log/gclient.log gclient sync --force

run_with_log log/gyp_chromium.log python src/build/gyp_chromium -Dchannel=$CHANNEL
run_with_log log/build.log make $MAKE_ARGS mod_pagespeed_test pagespeed_automatic_test
run_with_log log/unit_test.log out/Release/mod_pagespeed_test
run_with_log log/unit_test.log out/Release/pagespeed_automatic_test

if [ -n "$PACKAGE_TARGET" ]; then
  MODPAGESPEED_ENABLE_UPDATES=1 run_with_log build.log \
    make $MAKE_ARGS $PACKAGE_TARGET
fi

# FIXME
#if [ "$(uname -m)" = x86_64 ]; then
#  BIT_SIZE_NAME=x64
#else
#  BIT_SIZE_NAME=ia32
#fi
#build_dir="$HOME/build/$RELEASE/$BIT_SIZE_NAME"
#release_dir="$HOME/release/$RELEASE/$BIT_SIZE_NAME"
#rm -rf "$release_dir"
#mkdir -p "$release_dir"
#mkdir -p "$release_dir"
#cp -f $PWD/out/Release/mod-pagespeed-${CHANNEL}* "$release_dir"
#echo Copy the unstripped .so files to a safe place for easier debugging later.
#NBITS=$(getconf LONG_BIT)
#cp $build_dir/src/out/Release/libmod_pagespeed.so \
#  "$release_dir"/unstripped_libmodpagespeed_${NBITS}_${EXT}.so
#cp $build_dir/src/out/Release/libmod_pagespeed_ap24.so \
#  "$release_dir"/unstripped_libmodpagespeed_ap24_${NBITS}_${EXT}.so

echo Build succeeded at $(date)

exit 0