# shellcheck shell=bash
# Shared helpers sourced by check-version.sh and update-version.sh.

REPO="domsvoboda/nexus-launcher"
APP_KEY="Nexus Launcher"
VERSIONS_JSON="artifacts/versions.json"

# "nix system:upstream AppImage arch suffix"
PLATFORMS=(
    "x86_64-linux:x86_64"
    "aarch64-linux:arm64"
)

# Current and legacy AppImage asset prefixes, in order of preference.
ASSET_PREFIXES=("Nexus-Launcher" "Xodus-Nexus")

github_api() {
    local auth_header=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth_header=(-H "Authorization: Bearer $GITHUB_TOKEN")
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        auth_header=(-H "Authorization: Bearer $GH_TOKEN")
    fi
    curl -fsSL "${auth_header[@]}" -H "Accept: application/vnd.github+json" "https://api.github.com/$1"
}

# Prints the JSON of the newest stable launcher release. The repository also
# publishes backend releases (tagged "backend-v*"), so /releases/latest can't
# be used; only "vX.Y.Z" tags are launcher releases.
latest_release_json() {
    github_api "repos/$REPO/releases?per_page=50" | jq -c '
        [ .[]
          | select(.draft == false and .prerelease == false)
          | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
        ]
        | sort_by(.tag_name | ltrimstr("v") | split(".") | map(tonumber))
        | last // empty'
}

# current_version -> version recorded in versions.json (or "none")
current_version() {
    jq -r --arg app "$APP_KEY" '.[$app].version // "none"' "$VERSIONS_JSON" 2>/dev/null || echo "none"
}
