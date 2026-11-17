#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq curl

set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

log_info() { echo -e "\033[0;32m[INFO]\033[0m $*" >&2; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p artifacts
if [[ ! -f "$VERSIONS_JSON" ]]; then
    echo "{}" > "$VERSIONS_JSON"
fi

log_info "Fetching latest Nexus Launcher release..."
RELEASE=$(latest_release_json)
if [[ -z "$RELEASE" ]]; then
    log_error "Failed to fetch the latest launcher release"
    exit 1
fi

TAG=$(jq -r '.tag_name' <<< "$RELEASE")
VERSION="${TAG#v}"
CURRENT=$(current_version)

if [[ "$CURRENT" == "$VERSION" && "$FORCE" -eq 0 ]]; then
    log_info "Nexus Launcher is already at latest version ($VERSION). Skipping..."
    exit 0
fi

log_info "Updating Nexus Launcher: $CURRENT -> $VERSION"

# Finds the AppImage asset for an arch suffix, preferring the current
# "Nexus-Launcher-*" name over the legacy "Xodus-Nexus-*" one.
find_asset() {
    local arch="$1" prefix name
    for prefix in "${ASSET_PREFIXES[@]}"; do
        name="${prefix}-${VERSION}-${arch}.AppImage"
        if jq -e --arg n "$name" '.assets[] | select(.name == $n)' <<< "$RELEASE" > /dev/null; then
            echo "$name"
            return 0
        fi
    done
    return 1
}

payload=$(jq -n --arg v "$VERSION" '{version: $v}')

for plat in "${PLATFORMS[@]}"; do
    IFS=':' read -r nix_system arch <<< "$plat"

    if ! asset=$(find_asset "$arch"); then
        log_warn "No AppImage for $arch in $TAG; $nix_system will be unsupported in this version"
        continue
    fi

    url=$(jq -r --arg n "$asset" '.assets[] | select(.name == $n) | .browser_download_url' <<< "$RELEASE")

    log_info "Prefetching $asset ($nix_system)..."
    if ! prefetch=$(nix-prefetch-url --type sha256 --print-path "$url"); then
        log_error "Failed to prefetch $url"
        exit 1
    fi
    hash=$(sed -n 1p <<< "$prefetch")
    store_path=$(sed -n 2p <<< "$prefetch")

    # Verify against the upstream .sha512sum sidecar when it is published.
    sidecar_url=$(jq -r --arg n "$asset.sha512sum" '.assets[] | select(.name == $n) | .browser_download_url' <<< "$RELEASE")
    if [[ -n "$sidecar_url" ]]; then
        expected=$(curl -fsSL "$sidecar_url" | awk '{print $1}')
        actual=$(sha512sum "$store_path" | awk '{print $1}')
        if [[ "$expected" != "$actual" ]]; then
            log_error "SHA-512 mismatch for $asset (expected $expected, got $actual)"
            exit 1
        fi
        log_info "Verified $asset against upstream SHA-512 checksum"
    else
        log_warn "No .sha512sum sidecar for $asset; skipping upstream checksum verification"
    fi

    payload=$(jq --arg plat "$nix_system" --arg url "$url" --arg hash "$hash" \
        '.[$plat] = {url: $url, hash: $hash}' <<< "$payload")
done

if ! jq -e '.["x86_64-linux"]' <<< "$payload" > /dev/null; then
    log_error "Release $TAG has no x86_64 AppImage; refusing to update"
    exit 1
fi

tmp_json=$(mktemp)
jq --arg app "$APP_KEY" --argjson payload "$payload" '.[$app] = $payload' "$VERSIONS_JSON" > "$tmp_json"
mv "$tmp_json" "$VERSIONS_JSON"

log_info "Done! Updated $VERSIONS_JSON to $VERSION"
