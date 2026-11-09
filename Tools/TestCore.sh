#!/bin/zsh
set -euo pipefail
ProjectRoot="${0:A:h:h}"
cd "$ProjectRoot"
TestFile="$(mktemp /tmp/FilesLab-Core.XXXXXX.swift)"
trap 'unlink "$TestFile"' EXIT
cat worse_query/FileTypes.swift worse_query/FileOperations.swift worse_query/FolderPresentation.swift Tests/CoreChecks.swift > "$TestFile"
xcrun swift "$TestFile"
