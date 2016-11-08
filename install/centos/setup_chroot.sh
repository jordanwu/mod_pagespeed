#!/bin/bash
# Copyright 2016 Google Inc. All Rights Reserved.
# Author: cheesy@google.com (Steve Hill)
#
# Setup a 32-bit chroot for CentOS.

set -e
set -u

centos_version="$(lsb_release -rs)"

# TODO(cheesy): This is not especially robust, but right now I'm not inclined
# to try and scrape the site to find the most recent version.
if version_compare "$centos_version" -lt 6; then
  release_rpm=http://mirror.centos.org/centos/5/os/i386/CentOS/centos-release-5-11.el5.centos.i386.rpm
elif version_compare "$centos_version" -lt 7; then
  release_rpm=http://mirror.centos.org/centos/6/os/i386/Packages/centos-release-6-8.el6.centos.12.3.i686.rpm
else
  release_rpm=http://mirror.centos.org/altarch/7/os/i386/Packages/centos-release-7-2.1511.el7.centos.2.9.i686.rpm
fi

#CENTOS_KEY=https://centos.org/keys/RPM-GPG-KEY-CentOS-5

# This comes from build_env.sh.
if [ -d "$CHROOTDIR" ]; then
  echo "Chroot already exists!" >&2
  exit 1
fi

if [ "$UID" != 0 ]; then
  echo "This script needs to run as root, re-running with sudo"
  exec sudo $0 "@"
  exit 1  # NOTREACHED
fi

yum -y install setarch

#wget $CENTOS_KEY
#rpm --import $(basename $CENTOS_KEY)
wget -O /tmp/$(basename $release_rpm) $release_rpm

mkdir -p $CHROOTDIR/var/lib/rpm

set -x

function cleanup_etc_rpm_platform() {
  if [ -s /etc/rpm/platform.real ]; then
    mv -f /etc/rpm/platform.real /etc/rpm/platform
  elif [ -f /etc/rpm/platform.real ]; then
    # Only do this if platform.real exists, otherwise we could delete a
    # perfectly valid file.
    rm -f /etc/rpm/platform /etc/rpm/platform.real
  fi
}

# To force install a different architecture, we must put a fake arch into
# /etc/rpm/platform. Older CentOSes will have the file, newer may not. Either
# way, it's important that we don't leave the fake one lying around.
trap 'cleanup_etc_rpm_platform'  EXIT
if [ -e /etc/rpm/platform ]; then
  mv /etc/rpm/platform /etc/rpm/platform.real
else
  touch /etc/rpm/platform.real
fi

echo i686-redhat-linux > /etc/rpm/platform
rpm --rebuilddb --root=$CHROOTDIR
rpm --root=$CHROOTDIR --nodeps -i /tmp/$(basename $release_rpm)

yum -y --installroot=$CHROOTDIR update
# sudo is required for run_in_chroot.sh
yum -y --installroot=$CHROOTDIR install rpm-build yum sudo

cleanup_etc_rpm_platform
trap - EXIT

for x in passwd shadow group gshadow hosts sudoers resolv.conf; do
  ln -f /etc/$x $CHROOTDIR/etc/$x
done

cp -p /etc/yum.repos.d/* $CHROOTDIR/etc/yum.repos.d/
# FIXME - Clean this up
rm -f $CHROOTDIR/etc/yum.repos.d/CentOS-SCLo-scl[.-]*

for dir in /proc /sys /dev /selinux /etc/selinux /home; do
  [ -d $dir ] || continue
  chroot_dir=${CHROOTDIR}$dir
  if [ ! -d $chroot_dir ]; then
    mkdir -p $chroot_dir
    chown --reference $dir $chroot_dir
    chmod --reference $dir $chroot_dir
  fi
  echo "$dir $chroot_dir none bind 0 0" >> /etc/fstab
done

echo "none $CHROOTDIR/dev/shm tmpfs defaults 0 0" >> /etc/fstab

mount -a

git_pkg=''
# FIXME - is v6 correct when gclient is gone?
if version_compare "$(lsb_release -rs)" -ge 6; then
  git_pkg='git'
fi

# run_in_chroot doesn't work until lsb_release is installed.
/usr/bin/setarch i386 /usr/sbin/chroot /var/chroot/centos_i386 \
  /usr/bin/yum -y install redhat-lsb

# The yum install above probably did all the updates, but it doesn't hurt
# to ask.
install/run_in_chroot.sh yum -y update
install/run_in_chroot.sh yum -y install which redhat-lsb curl wget $git_pkg

if [ -z "$git_pkg" ]; then
  install/run_in_chroot.sh install/install_from_source.sh git
fi
