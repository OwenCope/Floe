#!/usr/bin/env bash
# Builds Floe.xcodeproj and merges the strings the compiler found into the String Catalog.
# A build writes them beside the object files (SWIFT_EMIT_LOC_STRINGS); only the Xcode app
# writes them into the catalog by itself, so a command line build needs this step.
#
# Usage:
#   ./scripts/sync-strings.sh          # build, then update the catalog
#   ./scripts/sync-strings.sh --check  # build, then fail if the catalog would change
set -euo pipefail
cd "$(dirname "$0")/.."

CATALOG="Sources/Floe/Resources/Localizable.xcstrings"
# Its own folder: sharing devrun.sh's leaves that build a module scan of the wrong configuration.
DERIVED=".build/xcode-strings"
OBJECTS="$DERIVED/Build/Intermediates.noindex/Floe.build/Debug/Floe.build/Objects-normal/$(uname -m)"

xcodebuild -project Floe.xcodeproj -scheme Floe -configuration Debug -derivedDataPath "$DERIVED" -quiet build

# One file per source file that exists now; a deleted file's leftover is not read.
args=()
while IFS= read -r source; do
    data="$OBJECTS/$(basename "$source" .swift).stringsdata"
    if [[ -f "$data" ]]; then args+=(--stringsdata "$data"); fi
done < <(find Sources/Floe -name '*.swift' | sort)

if [[ "${1:-}" == "--check" ]]; then
    copy=$(mktemp -d)/Localizable.xcstrings
    cp "$CATALOG" "$copy"
    xcrun xcstringstool sync "$copy" "${args[@]}"
    cmp -s "$CATALOG" "$copy" || {
        echo "error: $CATALOG is out of date; run ./scripts/sync-strings.sh" >&2
        exit 1
    }
    echo "$CATALOG is up to date"
else
    xcrun xcstringstool sync "$CATALOG" "${args[@]}"
    echo "Updated $CATALOG"
fi
