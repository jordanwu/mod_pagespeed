#!/bin/bash

this_dir="$(dirname "${BASH_SOURCE[0]}")"
source $this_dir/shell_library.sh || exit 1

buildtype=Release

if [ "${1:-}" = "--debug" ]; then
  buildtype=Debug
fi

echo Building PSOL binaries...

MAKE_ARGS=(V=1 BUILDTYPE=$buildtype)

run_with_log log/psol_build.log make "${MAKE_ARGS[@]}" \
  mod_pagespeed_test pagespeed_automatic_test

# Using a subshell for cd
(cd pagespeed/automatic && run_with_log ../../log/psol_automatic_build.log make "${MAKE_ARGS[@]}" \
  MOD_PAGESPEED_ROOT=$this_dir/.. CXXFLAGS="-DSERF_HTTPS_FETCHING=1" \
  all)

source net/instaweb/public/VERSION
VERSION="$MAJOR.$MINOR.$BUILD.$PATCH"

version_h=out/$buildtype/obj/gen/net/instaweb/public/version.h
if [ ! -f $version_h ]; then
  echo "Missing $version_h" >&2
  exit 1
fi

# FIXME - Not sure this test is really worth it...
if ! grep -q "^#define MOD_PAGESPEED_VERSION_STRING \"$VERSION\"$" \
          $version_h; then
  echo "Wrong version found in $version_h" >&2
  exit 1
fi

if [ -e psol ] ; then
  echo "A psol/ directory already exists.  Move it somewhere else and rerun."
  exit 1
fi
mkdir psol/

if [ $(uname -m) = x86_64 ]; then
  BIT_SIZE_NAME=x64
else
  BIT_SIZE_NAME=ia32
fi
BINDIR=psol/lib/$buildtype/linux/$BIT_SIZE_NAME
mkdir -p $BINDIR

cp -f pagespeed/automatic/pagespeed_automatic.a $BINDIR/
if [ "$buildtype" = "Release" ]; then
  cp -f out/Release/js_minify $BINDIR/pagespeed_js_minify
fi

echo Copying files to psol directory...

rsync -arz "." "psol/include/" --prune-empty-dirs \
  --exclude=".svn" \
  --exclude=".git" \
  --include='*.h' \
  --include='*/' \
  --include="apr_thread_compatible_pool.cc" \
  --include="serf_url_async_fetcher.cc" \
  --include="apr_mem_cache.cc" \
  --include="key_value_codec.cc" \
  --include="apr_memcache2.c" \
  --include="loopback_route_fetcher.cc" \
  --include="add_headers_fetcher.cc" \
  --include="console_css_out.cc" \
  --include="console_out.cc" \
  --include="dense_hash_map" \
  --include="dense_hash_set" \
  --include="sparse_hash_map" \
  --include="sparse_hash_set" \
  --include="sparsetable" \
  --include="mod_pagespeed_console_out.cc" \
  --include="mod_pagespeed_console_css_out.cc" \
  --include="mod_pagespeed_console_html_out.cc" \
  --exclude='*'

# Log that we did this.
REPO="$(git config --get remote.origin.url)"
COMMIT="$(git rev-parse HEAD)"

DATE="$(date +%F)"
echo "${DATE}: Copied from mod_pagespeed ${REPO}@${COMMIT} ($USER)" \
  >> psol/include_history.txt

echo Creating tarball...
tar -czf psol-${VERSION}-${BIT_SIZE_NAME}.tar.gz psol

echo Cleaning up...

echo PSOL $buildtype build succeeded at $(date)
