#!/bin/sh

# FIXME - this is duped from chroot setup

DISTRO=$(lsb_release -cs)
CHROOT_NAME=${DISTRO}_i386

exec schroot -c "$CHROOT_NAME" -- "$@"
