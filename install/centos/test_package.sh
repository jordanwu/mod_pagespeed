#!/bin/bash
# Copyright 2016 Google Inc. All Rights Reserved.
# Author: cheesy@google.com (Steve Hill)
#
# Install a mod_pagespeed rpm and run tests on it.

if [ $# -ne 1 ]; then
  echo "Usage: $(basename $0) <pagespeed_rpm>" >&2
  exit 1
fi

if [ $UID -ne 0 ]; then
  echo "This script requires root. Re-execing myself with sudo"
  exec sudo "$0" "$@"
  exit 1  # NOTREACHED
fi

pkg="$1"

echo Purging old releases...
# rpm --erase only succeeds if all packages listed are installed, so we need
# to find which one is installed and only erase that.
rpm --query mod-pagespeed-stable mod-pagespeed-beta | \
    grep -v "is not installed" | \
    xargs --no-run-if-empty sudo rpm --erase

mkdir -p log

echo "Installing $pkg..."
run_with_log log/install.log rpm --install "$pkg"

echo Test restart to make sure config file is valid ...
run_with_log log/install.log make -C install apache_debug_restart

echo Testing release ...
run_with_log log/system_test.log make -C install apache_vm_system_tests
