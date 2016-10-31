#!/bin/bash

this_dir="$( dirname "${BASH_SOURCE[0]}" )"
source $(dirname "$BASH_SOURCE")/../build_env.sh || exit 1

if [ $# -ne 1 ]; then
  echo "Usage: $(basename $0) <pagespeed_rpm>" >&2
  exit 1
fi
pkg=$1

if [ $UID -ne 0 ]; then
  exec sudo "$0" "$@"
  exit 1  # NOTREACHED
fi

echo Purging old releases...
# rpm --erase only succeeds if all packages listed are installed, so we need
# to find which one is installed and only erase that.
rpm --query mod-pagespeed-stable mod-pagespeed-beta | \
    grep -v "is not installed" | \
    xargs --no-run-if-empty sudo rpm --erase

mkdir -p log

echo Installing $pkg...
run_with_log log/install.log rpm --install "$pkg"

echo Test restart to make sure config file is valid ...
run_with_log log/install.log $this_dir/../invoke_make.sh -C install apache_debug_restart

echo Testing release ...
run_with_log log/system_test.log $this_dir/../invoke_make.sh -C install enable_ports_and_file_access apache_vm_system_tests
