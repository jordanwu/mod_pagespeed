#!/bin/bash

echo Purging old releases ...
if [ "$EXT" = "rpm" ] ; then
  # rpm --erase only succeeds if all packages listed are installed, so we need
  # to find which one is installed and only erase that.
  rpm --query mod-pagespeed-stable mod-pagespeed-beta | \
      grep -v "is not installed" | \
      xargs --no-run-if-empty sudo rpm --erase
else
  # dpkg --purge succeeds even if one or both of the packages is not installed.
  sudo dpkg --purge mod-pagespeed-beta mod-pagespeed-stable
fi

echo Installing release ...
check install.log sudo $INSTALL "$release_dir"/*.$EXT

echo Test restart to make sure config file is valid ...
cd $build_dir/src/install
check install.log sudo -E $RESTART

echo Testing release ...
check system_test.log sudo -E $TEST
