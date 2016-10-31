#!/bin/bash

set -e
set -u

source $(dirname "$BASH_SOURCE")/shell_utils.sh

if [ "$(lsb_release -is)" = "CentOS" ]; then
  devtoolset_enable=/opt/rh/devtoolset-2/enable
  if [ -f "$devtoolset_enable" ]; then
    # devtoolset_enable is not "set -u clean".
    set +u
    source "$devtoolset_enable"
    set -u
  fi

  export SSL_CERT_DIR=/etc/pki/tls/certs
  export SSL_CERT_FILE=/etc/pki/tls/cert.pem

  # TODO(cheesy) - is -std=c99 still required?
  export CFLAGS="-DGPR_MANYLINUX1 -std=gnu99 ${CFLAGS:-}"
else
  compiler_path=/usr/lib/gcc-mozilla
  if [ -x "${compiler_path}/bin/gcc" ]; then
    export PATH="${compiler_path}/bin:$PATH"
    export LD_LIBRARY_PATH="${compiler_path}/lib:${LD_LIBRARY_PATH:-}"
  fi
fi

export PATH=$HOME/bin:/usr/local/bin:$PATH
