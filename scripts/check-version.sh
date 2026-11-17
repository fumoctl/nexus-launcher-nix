#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq curl

set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Checking Nexus Launcher versions..."
echo ""

if [[ ! -f "$VERSIONS_JSON" ]]; then
    echo -e "${RED}Error: $VERSIONS_JSON not found. Run update-version.sh first!${NC}"
    exit 1
fi

current=$(current_version)
echo -e "Current version: $current"

latest=$(latest_release_json | jq -r '.tag_name // empty' | sed 's/^v//' || true)

if [[ -z "$latest" ]]; then
    echo -e "${RED}Error: Could not determine the latest upstream release${NC}"
    exit 1
fi

echo -e "Latest version:  $latest"

if [[ "$current" == "$latest" ]]; then
    echo -e "${GREEN}✓ Already at latest version!${NC}"
else
    echo -e "${YELLOW}⚠ Update available!${NC}"
fi
