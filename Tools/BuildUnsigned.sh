#!/bin/zsh
set -euo pipefail
ProjectRoot="${0:A:h:h}"
cd "$ProjectRoot"
xcodebuild -project worse_query.xcodeproj -scheme worse_query -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
print 'Unsigned build: build/Build/Products/Debug-iphoneos/worse_query.app'
print 'Configure your own team, bundle ID, and App Group in Xcode to install on a device.'
