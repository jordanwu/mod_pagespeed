#!/bin/bash

source $(dirname "$BASH_SOURCE")/build_env.sh || exit 1

install_from_src "$@"
