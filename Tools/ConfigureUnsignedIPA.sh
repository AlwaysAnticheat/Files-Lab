#!/bin/zsh
set -euo pipefail
if (( $# != 4 )); then
    print -u2 'Usage: Tools/ConfigureUnsignedIPA.sh INPUT.ipa BUNDLE_ID APP_GROUP_ID OUTPUT.ipa'
    exit 2
fi
Input="${1:A}"
BundleId="$2"
AppGroup="$3"
Output="${4:A}"
if [[ ! -f "$Input" || "$Input" == "$Output" ]]; then
    print -u2 'Provide an existing input IPA and a different output path.'
    exit 2
fi
if [[ ! "$BundleId" =~ '^[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$' || ! "$AppGroup" =~ '^group\.[A-Za-z0-9.-]+$' ]]; then
    print -u2 'Use a valid reverse-DNS bundle ID and an App Group ID beginning with group.'
    exit 2
fi
Stage="$(mktemp -d /tmp/FilesLabConfigure.XXXXXX)"
Cleanup() {
    python3 - "$Stage" <<'PY'
import shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY
}
trap Cleanup EXIT
unzip -q "$Input" -d "$Stage"
App="$Stage/Payload/worse_query.app"
if [[ ! -f "$App/Info.plist" ]]; then
    print -u2 'The input is not a Files Lab IPA.'
    exit 2
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BundleId" "$App/Info.plist"
/usr/libexec/PlistBuddy -c "Set :FilesLabAppGroup $AppGroup" "$App/Info.plist"
if codesign --verify "$App" >/dev/null 2>&1; then
    print -u2 'The input is already signed; configure an unsigned build instead.'
    exit 2
fi
(cd "$Stage" && zip -0 -q -r "$Stage/FilesLab-configured-unsigned.ipa" Payload)
mkdir -p "${Output:h}"
mv "$Stage/FilesLab-configured-unsigned.ipa" "$Output"
print "Configured unsigned IPA: $Output"
