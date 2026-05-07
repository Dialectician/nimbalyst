#!/usr/bin/env bash
#
# ship-dogfood.sh
#
# Publishes a fresh dogfood build to git.agiterra.org/tankloop/Nymbalyst.
# - Versioned release tagged from package.json version (archival)
# - "dogfood-current" rolling release updated for the team's auto-updater
#
# Multi-platform: run from each build host (mac after build:mac:notarized,
# Windows after build:win:all). Assets accumulate in the same versioned
# release and rolling release as long as package.json version matches.
# Uploads are upserts -- existing assets with the same name are replaced.

set -euo pipefail

REPO_OWNER="tankloop"
REPO_NAME="Nymbalyst"
GITEA_HOST="git.agiterra.org"
GITEA_API="https://${GITEA_HOST}/api/v1/repos/${REPO_OWNER}/${REPO_NAME}"
RELEASE_DIR="packages/electron/release"
ROLLING_TAG="dogfood-current"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

LOG_FILE="${SHIP_DOGFOOD_LOG:-${TMPDIR:-/tmp}/ship-dogfood-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$(dirname "$LOG_FILE")"
: >"$LOG_FILE"

log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG_FILE"; }
say()  { echo "[ship-dogfood] $*"; log "$*"; }
warn() { echo "[ship-dogfood] WARN: $*" >&2; log "WARN: $*"; }
die()  { echo "[ship-dogfood] ERROR: $*" >&2; log "ERROR: $*"; exit 1; }

human_size() {
  local bytes=$1
  awk -v b="$bytes" 'BEGIN {
    split("B KB MB GB TB", units);
    i = 1;
    while (b >= 1024 && i < 5) { b = b / 1024; i++; }
    printf "%.1f %s", b, units[i];
  }'
}

file_size_bytes() {
  stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo 0
}

log "==== ship-dogfood start (pid=$$) ===="
say "Verbose log: ${LOG_FILE}"

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
[[ "$VERSION" == *-dogfood* ]] || die "Version must be a semver prerelease with -dogfood (e.g. 0.59.0-dogfood.1). Got: ${VERSION}"
TAG="v${VERSION}"

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
  "${RELEASE_DIR}"/latest-mac.yml \
  "${RELEASE_DIR}"/Nimbalyst-Windows-*.exe \
  "${RELEASE_DIR}"/Nimbalyst-Windows-*.exe.blockmap \
  "${RELEASE_DIR}"/latest.yml \
  "${RELEASE_DIR}"/RELEASE_NOTES.md; do
  for f in $pattern; do
    # Literal paths (latest.yml, latest-mac.yml, RELEASE_NOTES.md) bypass nullglob,
    # so explicitly skip ones that don't exist on this build host.
    [[ -f "$f" ]] && ARTIFACTS+=("$f")
  done
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
  log "api ${method} ${path}"
  curl -fsS -X "$method" -H "$AUTH_HEADER" "${GITEA_API}${path}" "$@" 2>>"$LOG_FILE"
}
create_release() {
  api POST /releases -H "Content-Type: application/json" -d "$(jq -nc \
    --arg tag "$1" --arg name "$2" --arg body "$3" \
    '{tag_name: $tag, name: $name, body: $body, draft: false, prerelease: false}')"
}
# upload_asset: POST one file as a release asset, with verbose logging.
# Logs: filename, size, HTTP status, elapsed time, average upload speed,
# and the response body if the call did not return 2xx.
upload_asset() {
  local release_id=$1; local file=$2
  local fname; fname=$(basename "$file")
  local fbytes; fbytes=$(file_size_bytes "$file")
  local fsize_h; fsize_h=$(human_size "$fbytes")
  local resp_file; resp_file=$(mktemp -t ship-dogfood-resp.XXXXXX)
  local started ended elapsed http_code curl_exit speed_h
  started=$(date +%s)
  log "upload start release=${release_id} file=${fname} bytes=${fbytes} (${fsize_h})"
  set +e
  http_code=$(curl -sS \
    -o "$resp_file" \
    -w '%{http_code}' \
    -X POST \
    -H "$AUTH_HEADER" \
    --max-time 1800 \
    --connect-timeout 30 \
    -F "attachment=@${file};filename=${fname}" \
    "${GITEA_API}/releases/${release_id}/assets?name=${fname}" 2>>"$LOG_FILE")
  curl_exit=$?
  set -e
  ended=$(date +%s)
  elapsed=$((ended - started))
  if (( elapsed > 0 && fbytes > 0 )); then
    speed_h=$(human_size $((fbytes / elapsed)))
    speed_h="${speed_h}/s"
  else
    speed_h="n/a"
  fi
  log "upload done  release=${release_id} file=${fname} http=${http_code} curl_exit=${curl_exit} elapsed=${elapsed}s speed=${speed_h}"
  if [[ "$curl_exit" -ne 0 || ! "$http_code" =~ ^2 ]]; then
    local body_excerpt; body_excerpt=$(head -c 2000 "$resp_file" 2>/dev/null | tr -d '\0')
    log "upload FAIL  file=${fname} http=${http_code} curl_exit=${curl_exit} body=${body_excerpt}"
    rm -f "$resp_file"
    warn "upload failed: ${fname} (${fsize_h}, HTTP ${http_code}, curl exit ${curl_exit}, ${elapsed}s)"
    if [[ -n "$body_excerpt" ]]; then
      printf '       response: %s\n' "$(echo "$body_excerpt" | head -c 200)" >&2
    fi
    return 1
  fi
  rm -f "$resp_file"
  return 0
}
list_assets() { api GET "/releases/$1/assets" 2>/dev/null || echo '[]'; }
delete_asset() {
  log "delete asset release=$1 asset_id=$2"
  api DELETE "/releases/$1/assets/$2" >/dev/null 2>>"$LOG_FILE" || true
}
upsert_asset() {
  local release_id=$1; local file=$2
  local fname; fname=$(basename "$file")
  local existing_id
  existing_id=$(list_assets "$release_id" | jq -r --arg n "$fname" '.[] | select(.name == $n) | .id' | head -1)
  if [[ -n "$existing_id" ]]; then
    log "upsert: existing asset id=${existing_id} for ${fname}; deleting before re-upload"
    delete_asset "$release_id" "$existing_id"
  fi
  upload_asset "$release_id" "$file"
}
get_release_id() {
  local out
  out=$(api GET "/releases/tags/$1" 2>/dev/null) || return 0
  echo "$out" | jq -r '.id // empty'
}
get_release_body() {
  local out
  out=$(api GET "/releases/tags/$1" 2>/dev/null) || return 0
  echo "$out" | jq -r '.body // empty'
}
delete_release() { api DELETE "/releases/$1" >/dev/null; }
delete_tag()     { api DELETE "/tags/$1" 2>/dev/null || true; }

say "Versioned release ${TAG}..."
existing_versioned=$(get_release_id "$TAG")
if [[ -n "$existing_versioned" ]]; then
  say "  reusing existing id=${existing_versioned} (multi-platform ship)"
  versioned_id="$existing_versioned"
else
  if [[ $DRY_RUN -eq 0 ]]; then
    body="Dogfood build of v${VERSION}. Built locally from main, signed and notarized.

Install: download the .dmg (macOS) or .exe (Windows) from this release. Auto-updates pull from \`${ROLLING_TAG}\`."
    resp=$(create_release "$TAG" "Dogfood ${VERSION}" "$body")
    versioned_id=$(echo "$resp" | jq -r .id)
    say "  created id=${versioned_id}"
  else
    versioned_id="<dry-run-new>"
    say "  would create new release"
  fi
fi
VERSIONED_OK=0
VERSIONED_FAIL=0
VERSIONED_FAILED_NAMES=()
if [[ $DRY_RUN -eq 0 ]]; then
  say "  upserting ${#ARTIFACTS[@]} assets..."
  for f in "${ARTIFACTS[@]}"; do
    if upsert_asset "$versioned_id" "$f"; then
      echo "    ✓ $(basename "$f")"
      VERSIONED_OK=$((VERSIONED_OK + 1))
    else
      echo "    ✗ $(basename "$f") -- see ${LOG_FILE}"
      VERSIONED_FAIL=$((VERSIONED_FAIL + 1))
      VERSIONED_FAILED_NAMES+=("$(basename "$f")")
    fi
  done
  say "  versioned: ${VERSIONED_OK} ok, ${VERSIONED_FAIL} failed"
fi
echo

say "Rolling release ${ROLLING_TAG}..."
existing_rolling=$(get_release_id "$ROLLING_TAG")
rolling_needs_reset=0
if [[ -n "$existing_rolling" ]]; then
  existing_body=$(get_release_body "$ROLLING_TAG")
  if echo "$existing_body" | grep -qF "v${VERSION}"; then
    say "  reusing existing id=${existing_rolling} (still at v${VERSION})"
    rolling_id="$existing_rolling"
  else
    say "  existing rolling release is at a different version -- resetting"
    rolling_needs_reset=1
  fi
fi
if [[ -z "${existing_rolling:-}" || $rolling_needs_reset -eq 1 ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    if [[ $rolling_needs_reset -eq 1 ]]; then
      delete_release "$existing_rolling"
      delete_tag "$ROLLING_TAG"
    fi
    body="Latest dogfood build. Auto-updater feed source. Currently at v${VERSION}.

Updated on every new build. Versioned releases like \`${TAG}\` are kept for archival."
    resp=$(create_release "$ROLLING_TAG" "Dogfood (current)" "$body")
    rolling_id=$(echo "$resp" | jq -r .id)
    say "  created id=${rolling_id}"
  else
    rolling_id="<dry-run-new>"
    say "  would create new rolling release"
  fi
fi
ROLLING_OK=0
ROLLING_FAIL=0
ROLLING_FAILED_NAMES=()
if [[ $DRY_RUN -eq 0 ]]; then
  say "  upserting ${#ARTIFACTS[@]} assets..."
  for f in "${ARTIFACTS[@]}"; do
    if upsert_asset "$rolling_id" "$f"; then
      echo "    ✓ $(basename "$f")"
      ROLLING_OK=$((ROLLING_OK + 1))
    else
      echo "    ✗ $(basename "$f") -- see ${LOG_FILE}"
      ROLLING_FAIL=$((ROLLING_FAIL + 1))
      ROLLING_FAILED_NAMES+=("$(basename "$f")")
    fi
  done
  say "  rolling: ${ROLLING_OK} ok, ${ROLLING_FAIL} failed"
fi
echo

say "DONE."
echo
echo "  Versioned: https://${GITEA_HOST}/${REPO_OWNER}/${REPO_NAME}/releases/tag/${TAG}"
echo "  Rolling:   https://${GITEA_HOST}/${REPO_OWNER}/${REPO_NAME}/releases/tag/${ROLLING_TAG}"
echo
DOWNLOAD_BASE="https://${GITEA_HOST}/${REPO_OWNER}/${REPO_NAME}/releases/download/${ROLLING_TAG}"
DMG_MATCHES=("${RELEASE_DIR}"/Nimbalyst-*-arm64.dmg)
EXE_MATCHES=("${RELEASE_DIR}"/Nimbalyst-Windows-*.exe)
[[ -e "${DMG_MATCHES[0]:-}" ]] && echo "  Team DMG:  ${DOWNLOAD_BASE}/$(basename "${DMG_MATCHES[0]}")"
[[ -e "${EXE_MATCHES[0]:-}" ]] && echo "  Team EXE:  ${DOWNLOAD_BASE}/$(basename "${EXE_MATCHES[0]}")"
echo "  Feed URL:  ${DOWNLOAD_BASE}/"
echo "  Log file:  ${LOG_FILE}"

# Final exit summary -- non-zero if any upload failed so callers (CI, wrappers)
# can detect a partial ship instead of being misled by the "DONE." line.
TOTAL_FAIL=$((${VERSIONED_FAIL:-0} + ${ROLLING_FAIL:-0}))
if [[ $TOTAL_FAIL -gt 0 ]]; then
  echo
  warn "${TOTAL_FAIL} upload(s) failed:"
  if [[ ${#VERSIONED_FAILED_NAMES[@]} -gt 0 ]]; then
    printf '  versioned: %s\n' "${VERSIONED_FAILED_NAMES[*]}" >&2
  fi
  if [[ ${#ROLLING_FAILED_NAMES[@]} -gt 0 ]]; then
    printf '  rolling:   %s\n' "${ROLLING_FAILED_NAMES[*]}" >&2
  fi
  echo "  Inspect ${LOG_FILE} for HTTP status, response bodies, and timing." >&2
  log "==== ship-dogfood end (FAIL ${TOTAL_FAIL}) ===="
  exit 1
fi
log "==== ship-dogfood end (OK) ===="
