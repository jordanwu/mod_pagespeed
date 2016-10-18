#!/bin/bash

this_dir="$(dirname "${BASH_SOURCE[0]}")"
source $this_dir/shell_library.sh

install_from_src "$@"
