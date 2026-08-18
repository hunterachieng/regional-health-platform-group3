#!/usr/bin/env bash
# =============================================================================
# scripts/capture-incident-evidence.sh
# -----------------------------------------------------------------------------
# Runs OPS-2201..2204 reproduction load (or docker kill for 2204) and saves
# Prometheus alert/rule JSON to evidence/ — no Grafana UI required.
#
# Prerequisites:
#   docker compose up -d
#   ROW_COUNT=10000 docker compose exec capacity-api bash /usr/local/bin/seed.sh
#   monitoring/alert-rules.yml mounted in Prometheus (see monitoring/prometheus.yml)
#
# Usage:
#   ./scripts/capture-incident-evidence.sh           # all four
#   ./scripts/capture-incident-evidence.sh 2204      # one incident
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROM="${PROMETHEUS_URL:-http://localhost:9091}"
BASE_URL="${BASE_URL:-http://localhost:3010}"
API_CONTAINER="${API_CONTAINER:-rh-g3-capacity-api}"
WAIT_ALERT_SEC="${WAIT_ALERT_SEC:-120}"
POLL_SEC="${POLL_SEC:-5}"

EV6="$ROOT/evidence/06-observability"
EV7="$ROOT/evidence/07-incidents"

log() { printf '>> %s\n' "$*"; }
die() { printf '!! %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing '$1'. Install it and re-run."
}

save_prom_snapshot() {
  local dir="$1"
  local label="$2"
  mkdir -p "$dir"
  curl -sf "$PROM/api/v1/alerts" > "$dir/alerts-${label}.json"
  curl -sf "$PROM/api/v1/rules" > "$dir/rules-${label}.json"
  log "Saved Prometheus snapshots → $dir/alerts-${label}.json"
}

alert_state() {
  local alert_name="$1"
  curl -sf "$PROM/api/v1/rules" \
    | python3 -c "
import sys, json
name = sys.argv[1]
data = json.load(sys.stdin)
for g in data.get('data', {}).get('groups', []):
    for r in g.get('rules', []):
        if r.get('name') == name:
            print(r.get('state', 'unknown'))
            raise SystemExit(0)
print('missing')
" "$alert_name"
}

wait_for_alert_state() {
  local alert_name="$1"
  local want_state="$2"
  local deadline=$((SECONDS + WAIT_ALERT_SEC))
  while [ "$SECONDS" -lt "$deadline" ]; do
    local state
    state="$(alert_state "$alert_name" || true)"
    log "  $alert_name → $state (want: $want_state)"
    if [ "$state" = "$want_state" ]; then
      return 0
    fi
    sleep "$POLL_SEC"
  done
  return 1
}

preflight() {
  need_cmd curl
  need_cmd python3
  need_cmd docker

  curl -sf "$PROM/-/ready" >/dev/null \
    || die "Prometheus not reachable at $PROM — run: docker compose up -d"

  curl -sf "$BASE_URL/healthz" >/dev/null \
    || die "API not reachable at $BASE_URL — run: docker compose up -d"

  local groups
  groups="$(curl -sf "$PROM/api/v1/rules" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',{}).get('groups',[])))")"
  [ "$groups" -gt 0 ] || die "No Prometheus rule groups loaded — fix monitoring/alert-rules.yml mount and recreate prometheus"

  if ! command -v k6 >/dev/null 2>&1; then
    log "k6 not found — installing via apt (GitHub release)..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates gnupg
    sudo gpg --batch --yes --no-tty -o /usr/share/keyrings/k6-archive-keyring.gpg --dearmor \
      <<< "$(curl -fsSL https://dl.k6.io/key.gpg)" 2>/dev/null || true
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
      | sudo tee /etc/apt/sources.list.d/k6.list >/dev/null
    sudo apt-get update -qq && sudo apt-get install -y -qq k6 || die "Could not install k6 — see https://grafana.com/docs/k6/latest/set-up/install-k6/"
  fi

  mkdir -p "$EV6/panels" "$EV7/2201" "$EV7/2202" "$EV7/2203" "$EV7/2204"
  cp -f monitoring/alert-rules.yml "$EV6/alert-rules.yml"
  save_prom_snapshot "$EV6" "baseline"
  log "Preflight OK (API=$BASE_URL, Prometheus=$PROM)"
}

run_k6_incident() {
  local id="$1"
  local alert_name="$2"
  local script="$3"
  local out_dir="$EV7/$id"

  log "=== OPS-$id: k6 + alert $alert_name ==="
  mkdir -p "$out_dir"

  save_prom_snapshot "$out_dir" "before"

  log "Running k6 (background) → $out_dir/k6.log"
  BASE_URL="$BASE_URL" k6 run "$script" > "$out_dir/k6.log" 2>&1 &
  local k6_pid=$!

  if wait_for_alert_state "$alert_name" "pending" || wait_for_alert_state "$alert_name" "firing"; then
    save_prom_snapshot "$out_dir" "firing"
    cp -f "$out_dir/alerts-firing.json" "$EV6/panels/OPS-${id}-firing.json"
    log "Alert $alert_name reached pending/firing — evidence captured"
  else
    log "WARN: $alert_name did not reach pending/firing within ${WAIT_ALERT_SEC}s"
    save_prom_snapshot "$out_dir" "no-fire"
    echo "alert=${alert_name} did not fire within ${WAIT_ALERT_SEC}s" >> "$out_dir/notes.txt"
  fi

  wait "$k6_pid" || true
  save_prom_snapshot "$out_dir" "after"
  log "OPS-$id complete → $out_dir/"
}

run_2204_kill() {
  local out_dir="$EV7/2204"
  local alert_name="OPS2204ApiDown"

  log "=== OPS-2204: docker kill + alert $alert_name ==="
  mkdir -p "$out_dir"

  save_prom_snapshot "$out_dir" "before-kill"

  log "Killing $API_CONTAINER ..."
  docker kill "$API_CONTAINER" >/dev/null

  if wait_for_alert_state "$alert_name" "firing"; then
    save_prom_snapshot "$out_dir" "firing-kill"
    cp -f "$out_dir/alerts-firing-kill.json" "$EV6/panels/OPS-2204-firing.json"
    log "OPS2204ApiDown firing — evidence captured"
  else
    die "OPS2204ApiDown did not fire after docker kill"
  fi

  log "Waiting for API recovery..."
  local deadline=$((SECONDS + 90))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if curl -sf "$BASE_URL/healthz" >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done
  curl -sf "$BASE_URL/healthz" >/dev/null || log "WARN: API not healthy yet after 90s"

  sleep 20
  save_prom_snapshot "$out_dir" "after-recovery"

  log "Running k6 export storm (optional memory alert) → $out_dir/k6.log"
  BASE_URL="$BASE_URL" k6 run load-tests/reproduce-OPS-2204.js > "$out_dir/k6.log" 2>&1 || true
  save_prom_snapshot "$out_dir" "after-k6"

  if wait_for_alert_state "OPS2204MemoryHigh" "pending" 2>/dev/null || \
     wait_for_alert_state "OPS2204MemoryHigh" "firing" 2>/dev/null; then
    save_prom_snapshot "$out_dir" "memory-firing"
  fi

  log "OPS-2204 complete → $out_dir/"
}

run_one() {
  case "$1" in
    2201) run_k6_incident "2201" "OPS2201SearchP95High" "load-tests/reproduce-OPS-2201.js" ;;
    2202) run_k6_incident "2202" "OPS2202RecentP95High" "load-tests/reproduce-OPS-2202.js" ;;
    2203) run_k6_incident "2203" "OPS2203LockWaitTimeouts" "load-tests/reproduce-OPS-2203.js" ;;
    2204) run_2204_kill ;;
    *) die "Unknown incident '$1' — use 2201, 2202, 2203, or 2204" ;;
  esac
}

main() {
  preflight

  if [ "$#" -eq 0 ]; then
    run_one 2204
    run_one 2201
    run_one 2202
    run_one 2203
  else
    for id in "$@"; do
      run_one "$id"
    done
  fi

  log "Done. Evidence layout:"
  find evidence/06-observability evidence/07-incidents -type f 2>/dev/null | sort
}

main "$@"
