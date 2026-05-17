#!/bin/sh
# ---------------------------------------------------------------------------
# Firebase flavor-based GoogleService-Info.plist copy script
# Runs as an Xcode "Run Script" build phase BEFORE compilation.
# ---------------------------------------------------------------------------

# The FLAVOR xcconfig variable is set by Flutter via the flavor xcconfig files.
FLAVOR="${FLUTTER_APP_FLAVOR:-${CONFIGURATION}}"

# Normalise to lowercase prefix (Debug-dev → dev, Release-uat → uat, etc.)
FLAVOR_NAME=$(echo "$FLAVOR" | sed 's/.*-//' | tr '[:upper:]' '[:lower:]')

# Fall back to 'dev' if we can't determine the flavor (e.g. plain Debug/Release)
if [ -z "$FLAVOR_NAME" ] || [ "$FLAVOR_NAME" = "debug" ] || [ "$FLAVOR_NAME" = "release" ] || [ "$FLAVOR_NAME" = "profile" ]; then
  FLAVOR_NAME="dev"
fi

SRC="${PROJECT_DIR}/Runner/Firebase/${FLAVOR_NAME}/GoogleService-Info.plist"
DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"

echo "🔥 Firebase: Copying GoogleService-Info.plist for flavor '${FLAVOR_NAME}'"
echo "   Source: ${SRC}"
echo "   Destination: ${DEST}"

if [ ! -f "$SRC" ]; then
  echo "❌ Error: GoogleService-Info.plist not found at: ${SRC}"
  echo "   Please place the correct plist at Runner/Firebase/${FLAVOR_NAME}/GoogleService-Info.plist"
  exit 1
fi

cp -f "$SRC" "$DEST"
echo "✅ Done."
