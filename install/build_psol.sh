#!/bin/bash

echo Building PSOL binaries ...

for buildtype in Release Debug; do
  MAKE_ARGS=(V=1 BUILDTYPE=$buildtype)

  check psol_build.log make "${MAKE_ARGS[@]}"
    mod_pagespeed_test pagespeed_automatic_test

  pushd pagespeed/automatic/

  run_with_log log/psol_automatic_build.log make "${MAKE_ARGS[@]}" \
    MOD_PAGESPEED_ROOT=$build_dir/src CXXFLAGS="-DSERF_HTTPS_FETCHING=1" \
    all

  popd

  # FIXME
  #BINDIR=$HOME/psol_release/$RELEASE/psol/lib/$buildtype/linux/$BIT_SIZE_NAME
  #mkdir -p $BINDIR/
  #cp -f $automatic_dir/pagespeed_automatic.a $BINDIR/
  #if [ "$buildtype" = "Release" ]; then
  #  cp -f out/$buildtype/js_minify $BINDIR/pagespeed_js_minify
  #fi

  # Sync release binaries incrementally as they're built so we don't
  # lose progress.
  echo PSOL $buildtype build succeeded at $(date)
done
