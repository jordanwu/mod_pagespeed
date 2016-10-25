#!/bin/bash

set -e
set -u

GIT_VERSION=2.0.4
WGET_VERSION=1.12
MEMCACHED_VERSION=1.4.20
PYTHON_VERSION=2.7.8
REDIS_VERSION=3.2.4

GIT_SRC_URL=https://www.kernel.org/pub/software/scm/git/git-$GIT_VERSION.tar.gz
WGET_SRC_URL=http://ftp.gnu.org/gnu/wget/wget-$WGET_VERSION.tar.gz
MEMCACHED_SRC_URL=http://www.memcached.org/files/memcached-$MEMCACHED_VERSION.tar.gz
PYTHON_SRC_URL=https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz
REDIS_SRC_URL=http://download.redis.io/releases/redis-$REDIS_VERSION.tar.gz

if [ "$(lsb_release -is)" = "CentOS" ]; then
  devtoolset_enable=/opt/rh/devtoolset-2/enable
  if [ -f $devtoolset_enable ]; then
    set +u
    source $devtoolset_enable
    set -u
  fi

  export SSL_CERT_DIR=/etc/pki/tls/certs
  export SSL_CERT_FILE=/etc/pki/tls/cert.pem

  # FIXME - is -std=c99 still required?
  export CFLAGS="-DGPR_MANYLINUX1 -std=gnu99 ${CFLAGS:-}"
else
  compiler_bin=/usr/lib/gcc-mozilla/bin
  if [ -d $compiler_bin ]; then
    PATH=$compiler_bin:$PATH
  fi
fi

PATH=$HOME/bin:/usr/local/bin:$PATH

function install_from_src() {
  local pkg
  for pkg in "$@"; do
    if [ -e "/usr/local/bin/$pkg" ]; then
      echo "$pkg already installed, will not re-install"
      continue
    fi

    case "$pkg" in
      git) [ "$(lsb_release -is)" = "CentOS" ] && yum -y install curl-devel;
           install_src_tarball $GIT_SRC_URL ;;
      memcached) install_src_tarball $MEMCACHED_SRC_URL ;;
      python2.7) install_src_tarball $PYTHON_SRC_URL altinstall && \
        mkdir ~/bin && ln -s /usr/local/bin/python2.7 ~/bin/python ;;
      wget) install_src_tarball $WGET_SRC_URL ;;
      redis-server) install_src_tarball $REDIS_SRC_URL ;;
      *) echo "Internal error: Unknown source package: $pkg" >&2; return 1 ;;
    esac
  done
}

function run_with_log() {
  local verbose=
  if [ "$1" = "--verbose" ]; then
    verbose=1
    shift
  fi

  local log_filename="$1"
  shift
  local start_msg="[$(date '+%k:%M:%S')] $@"
  # echo what we're about to do to stdout, including log file location.
  echo "$start_msg >> $log_filename"
  # Now write the same thing to the log.
  echo "$start_msg" >> "$log_filename"
  local rc=0
  if [ -n "$verbose" ]; then
    "$@" 2>&1 | tee -a "$log_filename"
    rc=${PIPESTATUS[0]}
  else
    "$@" >> "$log_filename" 2>&1 || { rc=$?; true; }
  fi
  echo "[$(date '+%k:%M:%S')] Completed with exit status $rc" >> $log_filename
  if [ $rc -ne 0 ]; then
    tail "$log_filename"
  fi
  return $rc
}

function version_compare() {
  local a=$1
  local comparator=$2
  local b=$3

  if [ "${a%[^0-9.]*}" != "$a" ]; then
    echo "Non-numeric version: $a" >&2
    exit 1
  fi

  if [ "${b%[^0-9.]*}" != "$b" ]; then
    echo "Non-numeric version: $b" >&2
    exit 1
  fi

  # -1 a < b, 1 a > b
  local difference=0

  while [ $difference -eq 0 ]; do
    if [ -z "$a" -a -z "$b" ]; then
      break
    elif [ -z "$a" ]; then
      # a="", b != "", therefore a < b
      difference=-1
      break
    elif [ -z "$b" ]; then
      # a != "", b="", therefore a > b
      difference=1
      break
    fi

    # Pull first N off the beginning of $a into $a_tok
    local a_tok="${a%%.*}"
    # Make $a the remainder.
    a="${a#*.}"
    [ "$a" = "$a_tok" ] && a=""  # Happens when there are no .s in $a

    local b_tok="${b%%.*}"
    b="${b#*.}"
    [ "$b" = "$b_tok" ] && b=""

    if [ "$a_tok" -lt "$b_tok" ]; then
      difference=-1
    elif [ "$b_tok" -gt "$b_tok" ]; then
      difference=1
    fi
  done

  [ $difference $comparator 0 ]
}

function install_src_tarball() {
  local url=$1
  local install_target=${2:-install}
  local filename=$(basename $url)
  local dirname=$(basename $filename .tar.gz)
  dirname=$(basename $dirname .tgz)

  local tmpdir="$(mktemp -d)"
  pushd $tmpdir
  wget $url
  tar -xf $filename
  cd $dirname && { if [ -e ./configure ]; then ./configure; fi; } && make && \
    echo Installing $dirname && sudo make $install_target
  popd
  rm -rf "$tmpdir"
}
