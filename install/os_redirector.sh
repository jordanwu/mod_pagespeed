#!/bin/bash

this_dir=$(dirname "$0")

distro=$(lsb_release -is | tr A-Z a-z)
if [ ! -d "$this_dir/$distro" ]; then
  echo "$distro is not a supported build platform!" >&2
  exit 1
fi

exec "$this_dir/$distro/$(basename $0)" "$@"
