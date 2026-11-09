#!/bin/zsh
set -euo pipefail
if (( $# != 2 )); then
    print -u2 'Usage: Tools/InstallSigned.sh DEVICE_ID /absolute/path/to/Signed.app-or.ipa'
    exit 2
fi
xcrun devicectl device install app --device "$1" "$2"
