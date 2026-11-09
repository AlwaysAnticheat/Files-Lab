#!/bin/zsh
set -euo pipefail
ProjectRoot="${0:A:h:h}"
cd "$ProjectRoot"
DerivedData="$ProjectRoot/build/UnsignedDerivedData"
xcodebuild -quiet -project worse_query.xcodeproj -scheme worse_query -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath "$DerivedData" \
    CODE_SIGNING_ALLOWED=NO clean build
App="$DerivedData/Build/Products/Debug-iphoneos/worse_query.app"
if codesign --verify "$App" >/dev/null 2>&1; then
    print -u2 'Build is signed; refusing to label it unsigned.'
    exit 1
fi
Stage="$(mktemp -d /tmp/FilesLabUnsigned.XXXXXX)"
Cleanup() {
    python3 - "$Stage" <<'PY'
import shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY
}
trap Cleanup EXIT
mkdir -p "$Stage/Payload"
ditto "$App" "$Stage/Payload/worse_query.app"
(cd "$Stage" && zip -0 -q -r "$Stage/FilesLab-unsigned.ipa" Payload)
mkdir -p build
mv "$Stage/FilesLab-unsigned.ipa" build/FilesLab-unsigned.ipa
print "Unsigned IPA: $ProjectRoot/build/FilesLab-unsigned.ipa"
