#!/bin/bash

set -e
set -u

REQUIRED_PACKAGES='subversion apache2 g++ gperf devscripts fakeroot git-core
  zlib1g-dev wget curl netcat-traditional net-tools rsync'

if version_compare $(lsb_release -rs) -lt 14.04; then
  REQUIRED_PACKAGES+=' gcc-mozilla'
fi

OPTIONAL_PACKAGES='memcached libapache2-mod-php5'

if [ "$UID" -ne 0 ]; then
  echo Re-execing myself with sudo
  exec sudo $0 "$@"
  exit 1  # NOTREACHED
fi

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
  install_from_src redis-server
fi
