#!/bin/bash

source $(dirname "$BASH_SOURCE")/build_env.sh || exit 1

build_type=Release
package_target=
log_verbose=
package_channel=beta

eval set -- "$(getopt --long build_deb,build_rpm,debug,release,verbose -o '' -- "$@")"

while [ $# -gt 0 ]; do
  case "$1" in
    --build_deb) package_target=linux_package_deb; shift ;;
    --build_rpm) package_target=linux_package_rpm; shift ;;
    --debug) build_type=Debug; shift ;;
    --release) package_channel=release; shift ;;
    --verbose) log_verbose=--verbose; shift ;;
    --) shift; break ;;
    *) echo "getopt error" >&2; exit 1 ;;
  esac
done

root="$(git rev-parse --show-toplevel)"
cd "$root"

if [ ! -d pagespeed -o ! -d third_party ]; then
  echo "Run this from your mod_pagesped client" >&2
  exit 1
fi

MAKE_ARGS=(BUILDTYPE=$build_type)

# TODO(cheesy): gclient will be going away soon.
if [ -d depot_tools ]; then
  (cd depot_tools && git pull)
else
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi

PATH="$PATH:$PWD/depot_tools"

rm -rf log
mkdir -p log

# TODO(cheesy): The 64-bit build writes artifacts into out/Release not
# out/Release_x64. The fix for that seems to be setting product_dir, see:
# https://groups.google.com/forum/#!topic/gyp-developer/_D7qoTgelaY

run_with_log $log_verbose log/gclient.log gclient config \
  https://github.com/pagespeed/mod_pagespeed.git --unmanaged --name="$PWD"
run_with_log $log_verbose log/gclient.log gclient sync --force

if [ -n "$package_target" ]; then
  # TODO(cheesy): We need this for -Dchannel :-/
  run_with_log $log_verbose log/gyp_chromium.log \
    python build/gyp_chromium -Dchannel="$package_channel" --depth=.
fi

run_with_log $log_verbose log/build.log make \
  "${MAKE_ARGS[@]}" mod_pagespeed_test pagespeed_automatic_test
run_with_log $log_verbose log/unit_test.log \
  out/Release/mod_pagespeed_test
run_with_log $log_verbose log/unit_test.log \
  out/Release/pagespeed_automatic_test

if [ -n "$package_target" ]; then
  MODPAGESPEED_ENABLE_UPDATES=1 run_with_log $log_verbose build.log \
    make "${MAKE_ARGS[@]}" $package_target
fi

echo "Build succeeded at $(date)"
