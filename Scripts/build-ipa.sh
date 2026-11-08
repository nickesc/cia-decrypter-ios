#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
xcodegen generate
xcodebuild -quiet -project CIADecrypter.xcodeproj -scheme CIADecrypter -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
package_root="$(mktemp -d "$project_root/build/ipa.XXXXXX")"
mkdir -p "$package_root/Payload"
ditto build/DerivedData/Build/Products/Release-iphoneos/CIADecrypter.app "$package_root/Payload/CIADecrypter.app"
ditto -c -k --keepParent "$package_root/Payload" build/CIADecrypter.ipa
printf 'IPA: %s/build/CIADecrypter.ipa\n' "$project_root"
