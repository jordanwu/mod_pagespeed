#!/bin/bash

set -e
set -u

this_dir=$(dirname "${BASH_SOURCE[0]}")
source "$this_dir/../shell_library.sh" || exit 1

intall_all=''
if [ "$1" = "--all" ]; then
  install_all=1
fi

# FIXME - Inconsistent caps.
REQUIRED_PACKAGES='subversion httpd gcc-c++ gperf make rpm-build \
  glibc-devel at curl-devel expat-devel gettext-devel openssl-devel zlib-devel \
  libevent-devel'

OPTIONAL_PACKAGES='php php-mbstring'

src_packages=''
optional_src_packages='redis'
install_sl_gcc=''

if version_compare "$(lsb_release -rs)" -ge 7; then
  REQUIRED_PACKAGES+=" python27 wget"
  OPTIONAL_PACKAGES+=" memcached"
elif version_compare "$(lsb_release -rs)" -ge 6; then
  install_sl_gcc=6
  REQUIRED_PACKAGES+=" python26 wget"
  optional_src_packages='memcached'
else
  install_sl_gcc=5
  src_packages='python wget'
  optional_src_packages='memcached'
fi

if [ -n "$install_sl_gcc" ]; then
  # The signing cert is the same for all versions.
  sudo curl -o /etc/pki/rpm-gpg/RPM-GPG-KEY-cern https://linux.web.cern.ch/linux/scientific6/docs/repository/cern/slc6X/i386/RPM-GPG-KEY-cern
  sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-cern
  # Have to use curl; wget can't parse their SAN.
  sudo curl -o /etc/yum.repos.d/slc${install_sl_gcc}-devtoolset.repo \
    https://linux.web.cern.ch/linux/scientific${install_sl_gcc}/docs/repository/cern/devtoolset/slc${install_sl_gcc}-devtoolset.repo
  REQUIRED_PACKAGES+=" devtoolset-2-gcc-c++ devtoolset-2-binutils"
fi

sudo yum update

install_packages="$REQUIRED_PACKAGES"
if [ -n "$install_all" ]; then
  install_packages="$install_packages $OPTIONAL_PACKAGES"
fi

sudo yum -y install $install_packages
# Make sure atd started after installation.
sudo /etc/init.d/atd restart

# To build on Centos 5/6 we need gcc 4.8 from scientific linux.  We can't
# export CC and CXX because some steps still use a literal "g++".  But #$%^
# devtoolset includes its own sudo, and we don't want that because it doesn't
# support -E, so rename it if it exists.
DEVTOOLSET_BIN=/opt/rh/devtoolset-2/root/usr/bin/
if [ -e "$DEVTOOLSET_BIN/sudo" ]; then
  sudo mv "$DEVTOOLSET_BIN/sudo" "$DEVTOOLSET_BIN/sudo.ignored"
fi

if [ -n "$install_all" ]; then
  src_packages+=" $optional_src_packages"
fi
install_from_src $src_packages

# FIXME - This should be in the build script, only if it's not already running.
sudo /usr/local/bin/memcached -d -u nobody -m 512 -p 11211 127.0.0.1

## FIXME - build and install necat
#http://download.insecure.org/stf/nc110.tgz
# Add "#include <resolv.h>" to netcat.c, then:
# gcc -O -lresolv -DLINUX -o nc netcat.c

# FIXME Python path fix?
#echo 'PATH="$HOME/bin:/usr/local/bin:/opt/rh/devtoolset-2/root/usr/bin:$PATH"' >> ~/.bashrc

# On Centos5, yum needs /usr/bin/python to be 2.4 and gclient needs python on
# your path to be 2.6 or later.
# Edit bin/depot_tools_gclient to change python to python2.7

# FIXME Need to add LogLevel to apache.conf or something
#/etc/httpd/conf/httpd.conf
