#!/usr/bin/env bash
#
# ship-dogfood.sh
#
# Publishes a fresh dogfood build to git.agiterra.org/tankloop/Nymbalyst.
# - Versioned release tagged from package.json version (archival)
# - "dogfood-current" rolling release force-updated for the team's auto-updater

set -euo pipefail

REPO_OWNER="tankloop"
REPO_NAME="Nymbalyst"
GITEA_HOST="git.agiterra.org"
GITEA_API="https://${GITEA_HOST}/api/v1/repos/${REPO_OWNER}/${REPO_NAME}"
RELEASE_DIR="packages/electron/release"
ROLLING_TAG="dogfood-current"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

say() { echo "[ship-dogfood] $*"; }
die() { echo "[ship-dogfood] ERROR: $*" >&2; exit 1; }

if [[ -z "${GITEA_TOKEN:-}" ]]; then
  if [[ -f "$HOME/.config/agiterra/token" ]]; then
    GITEA_TOKEN=$(cat "$HOME/.config/agiterra/token")
  else
    die "GITEA_TOKEN not set and ~/.config/agiterra/token not found."
  fi
fi
AUTH_HEADER="Authorization: token ${GITEA_TOKEN}"

command -v curl >/dev/null || die "curl required"
command -v jq   >/dev/null || die "jq required (brew install jq)"
[[ -f packages/electron/package.json ]] || die "Run from the repo root."

VERSION=$(jq -r .version packages/electron/package.json)
[[ -z "$VERSION" || "$VERSION" == "null" ]] && die "Could not read version."
TAG="v${VERSION}-dogfood"

say "Repo:      ${REPO_OWNER}/${REPO_NAME}"
say "Version:   ${VERSION}"
say "Tag:       ${TAG}"
say "Rolling:   ${ROLLING_TAG}"
[[ $DRY_RUN -eq 1 ]] && say "(dry-run mode — no changes)"
echo

[[ -d "$RELEASE_DIR" ]] || die "$RELEASE_DIR not found. Run notarized build first."

shopt -s nullglob
ARTIFACTS=()
for pattern in \
  "${RELEASE_DIR}"/Nimbalyst-*-arm64.dmg \
  "${RELEASE_DIR}"/Nimbalyst-*-arm64.dmg.blockmap \
  "${RELEASE_DIR}"/Nimbalyst-*-arm64.zip \
  "${RELEASE_DIR}"/Nimbalyst-*-arm64.zip.blockmap \
  "${RELEASE_DIR}"/latest-mac.yml; do
  for f in $pattern; do ARTIFACTS+=("$f"); done
done
[[ ${#ARTIFACTS[@]} -eq 0 ]] && die "No artifacts found in ${RELEASE_DIR}."

say "Found ${#ARTIFACTS[@]} artifacts:"
for f in "${ARTIFACTS[@]}"; do
  size=$(du -h "$f" | awk '{print $1}')
  echo "   $size  $(basename "$f")"
done
echo

api() {
  local method=$1; shift
  local path=$1; shift
  curl -fsS -X "$method" -H "$AUTH_HEADER" "${GITEA_API}${path}" "$@"
}
create_release() {
  api POST /releases -H "Content-Type: application/json" -d "$(jq -nc \
    --arg tag "$1" --arg name "$2" --arg body "$3" \
    '{tag_name: $tag, name: $name, body: $body, draft: false, prerelease: false}')"
}
upload_asset() {
  local release_id=$1; local file=$2
  local fname; fname=$(basename "$file")
  curl -fsS -X POST -H "$AUTH_HEADER" \
    -F "attachment=@${file};filename=${fname}" \
    "${GITEA_API}/releases/${release_id}/assets?name=${fname}" >/dev/null
}
get_release_id() {
  local out
  out=$(api GET "/releases/tags/$1" 2>/dev/null) || return 0
  echo "$out" | jq -r '.id // empty'
}
delete_release() { api DELETE "/releases/$1" >/dev/null; }
delete_tag()     { api DELETE "/tags/$1" 2>/dev/null || true; }

say "Creating versioned release ${TAG}..."
[[ -n "$(get_release_id "$TAG")" ]] && die "Release ${TAG} already exists. Bump version or delete it manually."
if [[ $DRY_RUN -eq 0 ]]; then
  body="Dogfood build of v${VERSION}. Built locally from main, signed and notarized.

Install: download the .dmg from this release. Auto-updates pull from \`${ROLLING_TAG}\`."
  resp=$(create_release "$TAG" "Dogfood ${VERSION}" "$body")
  versioned_id=$(echo "$resp" | jq -r .id)
  say "  created id=${versioned_id}, uploading ${#ARTIFACTS[@]} assets..."
  for f in "${ARTIFACTS[@]}"; do upload_asset "$versioned_id" "$f"; echo "    ✓ $(basename "$f")"; done
fi
echo

say "Refreshing rolling release ${ROLLING_TAG}..."
existing_rolling=$(get_release_id "$ROLLING_TAG")
if [[ -n "$existing_rolling" ]]; then
  say "  deleting existing id=${existing_rolling}"
  if [[ $DRY_RUN -eq 0 ]]; then
    delete_release "$existing_rolling"
    delete_tag "$ROLLING_TAG"
  fi
fi
if [[ $DRY_RUN -eq 0 ]]; then
  body="Latest dogfood build. Auto-updater feed source. Currently at v${VERSION}.

Force-updated on every new build. Versioned releases like \`${TAG}\` are kept for archival."
  resp=$(create_release "$ROLLING_TAG" "Dogfood (current)" "$body")
  rolling_id=$(echo "$resp" | jq -r .id)
  say "  created id=${rolling_id}, uploading ${#ARTIFACTS[@]} assets..."
  for f in "${ARTIFACTS[@]}"; do upload_asset "$rolling_id" "$f"; echo "    ✓ $(basename "$f")"; done
fi
echo

say "DONE."
echo
echo "  Versioned: https://${GITEA_HOST}/${REPO_OWNER}/${REPO_NAME}/releases/tag/${TAG}"
echo "  Rolling:   https://${GITEA_HOST}/${REPO_OWNER}/${REPO_NAME}/releases/tag/${ROLLING_TAG}"
echo
DMG_NAME=$(basename "$(ls "${RELEASE_DIR}"/Nimbalyst-*-arm64.dmg 2>/dev/null | head -1)")
echo "  Team DMG:  https://${GITEA_HOST}/${REPO_OWNER}/${REPO_NAME}/releases/download/${ROLLING_TAG}/${DMG_NAME}"
echo "  Feed URL:  https://${GITEA_HOST}/${REPO_OWNER}/${REPO_NAME}/releases/download/${ROLLING_TAG}/"
