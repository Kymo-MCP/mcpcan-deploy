#!/usr/bin/env bash
set -euo pipefail

INSTANCE_BASE="http://localhost:31280"
SIDECAR_BASE="http://localhost:31281/mcp-gateway/debug-inst"

print_title() {
  printf "\n== %s ==\n" "$1"
}

print_cmd() {
  printf "+ %s\n" "$*"
}

fetch_session_id() {
  local base="$1"
  local hdr="/tmp/mcp-init-headers.txt"
  rm -f "${hdr}" /tmp/mcp-init-body.json || true
  curl -sS -D "${hdr}" -o /tmp/mcp-init-body.json \
    -X POST "${base}/mcp/" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    --data-binary '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"mcpcan-sidecar-smoke","version":"0.0.0"}}}' || true

  awk -F':' 'tolower($1)=="mcp-session-id"{gsub("\r","",$2); sub(/^ /,"",$2); print $2; exit}' "${hdr}" || true
}

show_initialize_result() {
  sed -n '1,30p' /tmp/mcp-init-headers.txt || true
  sed -n '1,80p' /tmp/mcp-init-body.json || true
}

send_initialized() {
  local base="$1"
  local sid="$2"
  curl -sS -i \
    -X POST "${base}/mcp/" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H "Mcp-Session-Id: ${sid}" \
    --data-binary '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' | sed -n '1,40p' || true
}

wait_ready() {
  local base="$1"
  local name="$2"
  print_title "Wait for ${name} ready"
  for i in $(seq 1 240); do
    if curl -sS -I --max-time 1 "${base}/sse" >/dev/null 2>&1; then
      echo "OK: ${name} is reachable"
      return 0
    fi
    sleep 0.5
  done
  echo "ERROR: ${name} not reachable after timeout"
  return 1
}

smoke_streamable_http() {
  local base="$1"
  print_title "Streamable HTTP @ ${base}/mcp/"

  print_cmd "POST ${base}/mcp/ initialize"
  local sid
  sid=$(fetch_session_id "$base")
  show_initialize_result
  if [[ -z "$sid" ]]; then
    echo "ERROR: Mcp-Session-Id not found in initialize response headers"
    exit 1
  fi
  echo "Mcp-Session-Id: ${sid}"

  print_cmd "POST ${base}/mcp/ notifications/initialized"
  send_initialized "$base" "$sid"

  print_cmd "POST ${base}/mcp/ tools/list (with Mcp-Session-Id)"
  curl -sS -i \
    -X POST "${base}/mcp/" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H "Mcp-Session-Id: ${sid}" \
    --data-binary '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | sed -n '1,120p'
}

probe_mcp_no_slash() {
  local base="$1"
  local name="$2"
  print_title "Probe /mcp (no trailing slash) @ ${name}"
  curl -sS -D - -o /dev/null \
    -X POST "${base}/mcp" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    --data-binary '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"mcpcan-sidecar-smoke","version":"0.0.0"}}}' \
    | sed -n '1,20p'
}

smoke_sse_legacy() {
  local base="$1"
  print_title "Legacy SSE @ ${base}/sse (show first 20 lines)"

  print_cmd "GET ${base}/sse"
  local tmp
  tmp=$(mktemp)
  curl -sS -N -i --max-time 3 \
    -H 'Accept: text/event-stream' \
    "${base}/sse" >"${tmp}" 2>/dev/null || true
  head -n 40 "${tmp}" || true
  rm -f "${tmp}" || true
}

smoke_sse_rewrite_check() {
  print_title "SSE endpoint rewrite check (sidecar should prefix /message)"
  print_cmd "GET ${SIDECAR_BASE}/sse"
  local tmp
  tmp=$(mktemp)
  curl -sS -N --max-time 3 \
    -H 'Accept: text/event-stream' \
    "${SIDECAR_BASE}/sse" >"${tmp}" 2>/dev/null || true

  cat "${tmp}" || true
  if grep -qE '^data: /mcp-gateway/debug-inst/message' "${tmp}"; then
    echo "OK: endpoint data path is prefixed"
  else
    echo "WARN: did not find prefixed endpoint data path in first lines"
  fi
  rm -f "${tmp}" || true
}

main() {
  print_title "Targets"
  echo "Instance: ${INSTANCE_BASE}"
  echo "Sidecar : ${SIDECAR_BASE}"

  wait_ready "${INSTANCE_BASE}" "mcp-debug-instance"
  wait_ready "${SIDECAR_BASE}" "mcp-debug-sidecar"

  smoke_sse_legacy "$INSTANCE_BASE"
  smoke_sse_legacy "$SIDECAR_BASE"
  smoke_sse_rewrite_check

  smoke_streamable_http "$INSTANCE_BASE"
  smoke_streamable_http "$SIDECAR_BASE"

  probe_mcp_no_slash "$INSTANCE_BASE" "instance"
  probe_mcp_no_slash "$SIDECAR_BASE" "sidecar"
}

main "$@"
