#!/bin/bash
# Publish a Hush release that existing copies can update to through Sparkle.
#   1. Bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist.
#   2. Commit your changes, then run: ./scripts/release.sh "What changed in this version."
# Builds and zips the universal app, signs the zip with the Sparkle key in your
# login Keychain, creates the GitHub release, then publishes appcast.xml on main.
set -euo pipefail
cd "$(dirname "$0")/.."
NOTES="${1:?Usage: ./scripts/release.sh \"Release notes\"}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
TAG="v$VERSION"
ZIP="build/Hush-$VERSION.zip"
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then echo "Release $TAG already exists. Bump the version in Info.plist."; exit 1; fi

./build.sh universal
# Releases must keep the same identity, or every update resets Accessibility.
codesign -dvv build/Hush.app 2>&1 | grep -q "^Authority=Hush Signing$" || { echo "Release must be signed with the Hush Signing certificate."; exit 1; }
rm -f "$ZIP"
ditto -c -k --keepParent build/Hush.app "$ZIP"
(cd build && shasum -a 256 "Hush-$VERSION.zip" > "Hush-$VERSION.sha256")
# Prints: sparkle:edSignature="…" length="…"
SIGNATURE="$(build/spm-arm64/artifacts/sparkle/Sparkle/bin/sign_update --account com.musaamir.hush "$ZIP")"

gh release create "$TAG" "$ZIP" "build/Hush-$VERSION.sha256" --title "Hush $VERSION" --notes "$NOTES"

cat > appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Hush</title>
    <item>
      <title>Hush $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>$NOTES</p>]]></description>
      <enclosure url="https://github.com/musaAmir/Hush/releases/download/$TAG/Hush-$VERSION.zip" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
git add appcast.xml
git commit -m "Publish Hush $VERSION to the update feed"
# The app reads the feed from main (SUFeedURL in Info.plist).
git push origin HEAD:main
echo "Released Hush $VERSION. Installed copies will see it on their next update check."
