#!/bin/zsh
set -euo pipefail
ProjectRoot="${0:A:h:h}"
cd "$ProjectRoot"
xcodebuild -project worse_query.xcodeproj -scheme worse_query -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
ConfiguredGroup="$(/usr/libexec/PlistBuddy -c 'Print :FilesLabAppGroup' build/Build/Products/Debug-iphoneos/worse_query.app/Info.plist)"
if [[ -z "$ConfiguredGroup" || "$ConfiguredGroup" == *'$('* ]]; then
    print -u2 'The runtime App Group value was not expanded in Info.plist.'
    exit 1
fi
print 'Unsigned build: build/Build/Products/Debug-iphoneos/worse_query.app'
print 'Configure your own team, bundle ID, and App Group in Xcode to install on a device.'
