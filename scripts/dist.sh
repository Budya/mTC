#!/bin/bash
# Собирает Release-версию mTC и упаковывает её в zip для раздачи команде:
#
#   build/mTC-<версия>.zip
#   └── mTC/
#       ├── mTC.app
#       ├── mTC-data/     (пустая, настройки появятся при первом запуске)
#       └── README.md
#
# Использование: scripts/dist.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
STAGE="$BUILD/stage/mTC"

cd "$ROOT"

VERSION=$(xcodebuild -project mTC.xcodeproj -scheme mTC -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }')

echo "==> Сборка mTC $VERSION (Release)"
xcodebuild -project mTC.xcodeproj -scheme mTC -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" build -quiet

APP="$DERIVED/Build/Products/Release/mTC.app"

echo "==> Подготовка папки поставки"
rm -rf "$BUILD/stage"
mkdir -p "$STAGE/mTC-data"
ditto --norsrc --noextattr "$APP" "$STAGE/mTC.app"
cp "$ROOT/README.md" "$STAGE/README.md"

# Командный пресет настроек: если есть dist-preset/, его содержимое кладётся в mTC-data/.
if [ -d "$ROOT/dist-preset" ]; then
    ditto "$ROOT/dist-preset" "$STAGE/mTC-data"
fi

ZIP="$BUILD/mTC-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent "$STAGE" "$ZIP"

echo "==> Готово: $ZIP"
