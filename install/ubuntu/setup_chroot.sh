#!/bin/bash

set -e

DISTRO=precise
CHROOT_NAME=${DISTRO}_i386
CHROOT_DIR=/var/chroot/$CHROOT_NAME

if [ -d $CHROOT_DIR ]; then
  echo Already ran, doing nothing.
  exit 0
fi

if [ "$UID" -ne 0 ]; then
  echo Re-execing myself with sudo
  exec sudo $0 "$@"
  exit 1  # NOTREACHED
fi

apt-get -y update
apt-get -y upgrade

apt-get install debootstrap dchroot

# Obliterate the chroot on failed setup. Note that we explicitly refuse to
# start if the chroot directory exists at startup.
trap '[ $? -ne 0 ] && rm -rf $CHROOT_DIR' EXIT

debootstrap --variant=buildd --arch i386 $DISTRO $CHROOT_DIR http://archive.ubuntu.com/ubuntu/

cat >> /etc/schroot/schroot.conf << EOF
[$CHROOT_NAME]
description=Ubuntu $DISTRO for i386
directory=$CHROOT_DIR
type=directory
personality=linux32
preserve-environment=true
root-groups=sudo
groups=sudo
EOF

cat >> /etc/schroot/default/fstab << EOF
none   /dev/shm   tmpfs   rw,nosuid,nodev,noexec 0 0
none   /run/shm   tmpfs   rw,nosuid,nodev,noexec 0 0
EOF

cp /etc/apt/sources.list $CHROOT_DIR/etc/apt
schroot -c $CHROOT_NAME -- apt-get -y update
schroot -c $CHROOT_NAME -- apt-get -y upgrade
schroot -c $CHROOT_NAME -- apt-get -y install gnupg locales sudo
schroot -c $CHROOT_NAME -- locale-gen en_US.UTF-8

cp /etc/sudoers $CHROOT_DIR/etc/sudoers
