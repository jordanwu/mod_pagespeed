#!/bin/bash

set -e
set -u

this_dir="$( dirname "${BASH_SOURCE[0]}" )"
source $(dirname "$BASH_SOURCE")/../shell_library.sh || exit 1

REQUIRED_PACKAGES='subversion apache2 g++ gperf devscripts fakeroot git-core
  zlib1g-dev wget curl netcat-traditional net-tools'

if version_compare $(lsb_release -rs) -lt 14.04; then
  REQUIRED_PACKAGES+=' gcc-mozilla'
fi

OPTIONAL_PACKAGES='memcached libapache2-mod-php5'

install_packages="$REQUIRED_PACKAGES"
install_redis_from_src=''
if [ "${1:-}" = "--all" ]; then
  install_packages="$install_packages $OPTIONAL_PACKAGES"
  if version_compare $(lsb_release -sr) -ge 14.04; then
    install_packages="redis-server"
  else
    install_redis_from_src=1
  fi
fi

apt-get -y install $install_packages
update-alternatives --set nc /bin/nc.traditional

if [ -n "$install_redis_from_src" ]; then
  install_from_src redis
fi
