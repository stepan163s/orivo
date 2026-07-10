#!/bin/bash
set -e

echo "=== Step 1: Generating Sparkle signature for Orivo.dmg ==="
SIGN_OUTPUT=$(.build/artifacts/sparkle/Sparkle/bin/sign_update Orivo.dmg)

ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
FILE_LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

if [ -z "$ED_SIGNATURE" ] || [ -z "$FILE_LENGTH" ]; then
    echo "Error: Failed to get signature or length from Sparkle tool."
    echo "Output was: $SIGN_OUTPUT"
    exit 1
fi

echo "Signature: $ED_SIGNATURE"
echo "Length: $FILE_LENGTH"

echo "=== Step 2: Updating appcast.xml ==="
FILE_LENGTH="$FILE_LENGTH" ED_SIGNATURE="$ED_SIGNATURE" python3 -c "
import os, re
file_length = os.environ['FILE_LENGTH']
ed_signature = os.environ['ED_SIGNATURE']
with open('appcast.xml', 'r') as f:
    content = f.read()

new_enclosure = f'<enclosure url=\"https://github.com/stepan163s/orivo/releases/download/v1.1.2/Orivo.dmg\" sparkle:version=\"1.1.2\" sparkle:shortVersionString=\"1.1.2\" length=\"{file_length}\" type=\"application/octet-stream\" sparkle:edSignature=\"{ed_signature}\" />'
content = re.sub(r'<enclosure url=\"https://github.com/stepan163s/orivo/releases/download/v1.1.2/Orivo.dmg\".*?/>', new_enclosure, content)

with open('appcast.xml', 'w') as f:
    f.write(content)
"

echo "=== Step 3: Committing and pushing to GitHub ==="
git add appcast.xml build.sh Sources/Orivo/Core/Settings/KeychainHelper.swift
git commit -m "chore: release v1.1.2 (removed Keychain prompt)" || true
git push origin main

echo "=== Step 4: Creating GitHub Release v1.1.2 ==="
# Delete old v1.1.2 release if exists to overwrite it
gh release delete v1.1.2 -y || true
git push --delete origin v1.1.2 || true
git tag -d v1.1.2 || true
gh release create v1.1.2 Orivo.dmg --title "v1.1.2" --notes "Release v1.1.2: Improved application security, updated encryption for settings and keys, resolved TorrServer player freezes, and optimized network stability."

echo "=== Done! Release v1.1.2 created successfully! ==="
