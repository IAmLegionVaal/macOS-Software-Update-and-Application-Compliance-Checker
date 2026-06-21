#!/bin/bash
set -u

DO_REPAIR=false
INSTALL_ALL=false
INSTALL_RECOMMENDED=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: macos_software_compliance_repair.sh [options]

  --repair               Restart software update and installer services.
  --install-all          Install all available macOS updates.
  --install-recommended  Install recommended macOS updates.
  --dry-run              Show actions without changing the Mac.
  --yes                  Skip confirmation prompts.
  --output DIR           Save logs and verification output in DIR.
  -h, --help             Show help.

Update installation can take a long time and may require a restart.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair) DO_REPAIR=true; shift ;;
    --install-all) INSTALL_ALL=true; DO_REPAIR=true; shift ;;
    --install-recommended) INSTALL_RECOMMENDED=true; DO_REPAIR=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 3; }
if $INSTALL_ALL && $INSTALL_RECOMMENDED; then echo "Choose one update installation mode." >&2; exit 2; fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./software-compliance-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
VERIFY="$OUTPUT_DIR/verification.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() {
  $ASSUME_YES && return 0
  printf '%s [y/N]: ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
run_action() {
  description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then
    printf 'DRY-RUN:' >> "$LOG"; for arg in "$@"; do printf ' %q' "$arg" >> "$LOG"; done; printf '\n' >> "$LOG"; return 0
  fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_admin() {
  description="$1"; shift
  if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" /usr/bin/sudo "$@"; fi
}
verify() {
  {
    echo "Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    /usr/bin/sw_vers
    echo
    echo "Software update services:"
    ps -Ao pid,user,etime,comm,args | grep -Ei 'softwareupdated|storedownloadd|installd|appstoreagent' | grep -v grep || true
    echo
    echo "Available updates:"
    /usr/sbin/softwareupdate -l 2>&1 || true
    echo
    echo "Recent update history:"
    /usr/sbin/softwareupdate --history 2>&1 | head -n 200 || true
  } > "$VERIFY" 2>&1
}

verify
if ! $DO_REPAIR; then log "Verification-only mode completed. Use repair options to apply changes."; exit 0; fi
if ! confirm "Restart software update and installer services?"; then log "Repair cancelled by user."; exit 10; fi

run_admin "Restarting software update service" /bin/launchctl kickstart -k system/com.apple.softwareupdated || \
  run_admin "Requesting software update process restart" /usr/bin/killall softwareupdated || true
if pgrep -x storedownloadd >/dev/null 2>&1; then run_admin "Restarting storedownloadd" /usr/bin/killall storedownloadd || true; fi
if pgrep -x installd >/dev/null 2>&1; then run_admin "Restarting installd" /usr/bin/killall installd || true; fi

if $INSTALL_RECOMMENDED && confirm "Install recommended macOS updates now?"; then
  run_admin "Installing recommended updates" /usr/sbin/softwareupdate -i -r || true
fi
if $INSTALL_ALL && confirm "Install all available macOS updates now? A restart may be required."; then
  run_admin "Installing all available updates" /usr/sbin/softwareupdate -i -a || true
fi

if ! $DRY_RUN; then sleep 5; fi
verify
if [ "$FAILURES" -gt 0 ]; then log "Repair completed with $FAILURES warning(s)."; exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
