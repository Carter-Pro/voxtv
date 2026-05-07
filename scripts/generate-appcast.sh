#!/bin/bash
set -euo pipefail

# Generate Sparkle appcast.xml for a release
# Usage: ./scripts/generate-appcast.sh <dmg-path> <download-url> <version>
# The DMG URL should be the direct download link from GitHub Releases

DMG_PATH="${1:?}"
DOWNLOAD_URL="${2:?}"
VERSION="${3:?}"

FILE_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat -c%s "$DMG_PATH" 2>/dev/null)

cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>VoxTV</title>
    <description>VoxTV releases</description>
    <language>en</language>
    <item>
      <title>VoxTV $VERSION</title>
      <description>VoxTV $VERSION</description>
      <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S GMT")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$DOWNLOAD_URL"
        sparkle:version="$VERSION"
        length="$FILE_SIZE"
        type="application/x-apple-diskimage"
      />
    </item>
  </channel>
</rss>
XML
