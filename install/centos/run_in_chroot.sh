#!/bin/bash

CHROOTDIR=/var/chroot/centos_i386
this_dir="$(dirname "${BASH_SOURCE[0]}")"

set -e
set -u

# It's really hard to make cd $dir && exec "$@" work so we just invoke ourself.
if [ "${1-}" = "--chroot_done" -a $# -ge 2 ]; then
  cd "$2"
  shift 2

  if [ $# -eq 0 ]; then
    set -- bash -l
  fi
  exec "$@"
  exit 1  # NOTREACHED
fi

if [[ "$this_dir" != /* ]]; then
  this_dir="$PWD/$this_dir"
fi

exec setarch i386 sudo /usr/sbin/chroot /var/chroot/centos_i386 sudo -u "$USER" -i -- \
  $this_dir/$(basename $0) --chroot_done "$PWD" "$@"
