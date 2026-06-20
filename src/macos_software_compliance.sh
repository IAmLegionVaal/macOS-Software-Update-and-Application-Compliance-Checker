#!/bin/bash
set -u

APP_PATH=""
OUTPUT_DIR=""
SKIP_UPDATE_SCAN=false

usage() { echo "Usage: macos_software_compliance.sh [--app PATH] [--skip-update-scan] [--output DIR]"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) APP_PATH="${2:-}"; shift 2 ;;
    --skip-update-scan) SKIP_UPDATE_SCAN=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 1; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./software-compliance-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/software-compliance.txt"
CSV="$OUTPUT_DIR/applications.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"
echo 'path,name,version,bundle_id,signature_valid,gatekeeper_status' > "$CSV"

section() { title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
section "Collection metadata" /bin/bash -c 'date -u +%Y-%m-%dT%H:%M:%SZ; hostname; sw_vers; id'
section "Install history" /usr/sbin/system_profiler SPInstallHistoryDataType
if ! $SKIP_UPDATE_SCAN; then section "Pending updates" /usr/sbin/softwareupdate -l; fi

TOTAL=0
UNSIGNED=0
MISSING_VERSION=0
for app in /Applications/*.app /Applications/*/*.app /System/Applications/*.app; do
  [ -d "$app" ] || continue
  TOTAL=$((TOTAL + 1))
  plist="$app/Contents/Info.plist"
  name=$(basename "$app" .app)
  version=""
  bundle_id=""
  [ -f "$plist" ] && version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)
  [ -z "$version" ] && [ -f "$plist" ] && version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || true)
  [ -f "$plist" ] && bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)
  signature_valid=false
  /usr/bin/codesign --verify --deep --strict "$app" >/dev/null 2>&1 && signature_valid=true
  gatekeeper="not-tested"
  if /usr/sbin/spctl --assess --type execute "$app" >/dev/null 2>&1; then gatekeeper="accepted"; else gatekeeper="rejected-or-unassessed"; fi
  [ "$signature_valid" = false ] && UNSIGNED=$((UNSIGNED + 1))
  [ -z "$version" ] && MISSING_VERSION=$((MISSING_VERSION + 1))
  safe() { printf '%s' "$1" | sed 's/"/""/g'; }
  printf '"%s","%s","%s","%s","%s","%s"\n' "$(safe "$app")" "$(safe "$name")" "$(safe "$version")" "$(safe "$bundle_id")" "$signature_valid" "$gatekeeper" >> "$CSV"
done

APP_ASSESSED=false
APP_SIGNATURE=false
APP_GATEKEEPER=false
if [ -n "$APP_PATH" ]; then
  APP_ASSESSED=true
  if [ -e "$APP_PATH" ]; then
    section "Selected application signature" /usr/bin/codesign -dvvv --entitlements :- "$APP_PATH"
    section "Selected application Gatekeeper assessment" /usr/sbin/spctl --assess --type execute -vv "$APP_PATH"
    /usr/bin/codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1 && APP_SIGNATURE=true
    /usr/sbin/spctl --assess --type execute "$APP_PATH" >/dev/null 2>&1 && APP_GATEKEEPER=true
  fi
fi

PENDING_UPDATES=0
if ! $SKIP_UPDATE_SCAN; then
  PENDING_UPDATES="$(/usr/sbin/softwareupdate -l 2>/dev/null | grep -c '^\* Label:' || true)"
fi
OVERALL="Compliant"
if [ "$UNSIGNED" -gt 0 ] || [ "$PENDING_UPDATES" -gt 0 ]; then OVERALL="Attention required"; fi

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "macos_version": "$(sw_vers -productVersion)",
  "build_version": "$(sw_vers -buildVersion)",
  "applications_audited": $TOTAL,
  "applications_with_invalid_or_missing_signatures": $UNSIGNED,
  "applications_missing_version_metadata": $MISSING_VERSION,
  "pending_updates": $PENDING_UPDATES,
  "selected_application": "$APP_PATH",
  "selected_application_assessed": $APP_ASSESSED,
  "selected_application_signature_valid": $APP_SIGNATURE,
  "selected_application_gatekeeper_accepted": $APP_GATEKEEPER,
  "overall_status": "$OVERALL"
}
EOF
printf '\nSoftware compliance collection completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
