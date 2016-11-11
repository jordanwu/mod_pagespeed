#!/bin/bash
# Copyright 2016 Google Inc. All Rights Reserved.
# Author: cheesy@google.com (Steve Hill)
#
# Install a mod_pagespeed deb and run tests on it.

if [ $# -ne 1 ]; then
  echo "Usage: $(basename $0) <pagespeed_deb>" >&2
  exit 1
fi

if [ $UID -ne 0 ]; then
  echo "This script requires root. Re-execing myself with sudo"
  exec sudo "$0" "$@"
  exit 1  # NOTREACHED
fi

pkg="$1"

echo Purging old releases...
dpkg --purge mod-pagespeed-beta mod-pagespeed-stable

mkdir -p log

echo "Installing $pkg..."
run_with_log log/install.log dpkg --install "$pkg"

echo Test restart to make sure config file is valid ...
run_with_log log/install.log make -C install apache_debug_restart

echo Testing release ...
run_with_log log/system_test.log make -C install apache_vm_system_tests
