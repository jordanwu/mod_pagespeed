#!/bin/bash

# FIXME - Remove ubuntu.sh and centos.sh

this_dir="$( dirname "${BASH_SOURCE[0]}" )"

if [ $# -ne 1 ]; then
  echo "Usage: $(basename $0) <pagespeed_deb>" >&2
  exit 1
fi
pkg=$1

if [ $UID -ne 0 ]; then
  exec sudo "$0" "$@"
  exit 1  # NOTREACHED
fi

echo Purging old releases...
dpkg --purge mod-pagespeed-beta mod-pagespeed-stable

mkdir -p log

echo Installing $pkg...
run_with_log log/install.log dpkg --install "$pkg"

echo Test restart to make sure config file is valid ...
run_with_log log/install.log $this_dir/../invoke_make.sh -C install apache_debug_restart

echo Testing release ...
run_with_log log/system_test.log $this_dir/../invoke_make.sh -C install apache_vm_system_tests
