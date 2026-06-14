#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/update/lib/environment.sh
source "${SCRIPT_DIR}/lib/environment.sh"
# shellcheck source=scripts/update/lib/results.sh
source "${SCRIPT_DIR}/lib/results.sh"
# shellcheck source=scripts/update/lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck source=scripts/update/lib/docker_desktop_credentials.sh
source "${SCRIPT_DIR}/lib/docker_desktop_credentials.sh"
# shellcheck source=scripts/lib/excalidraw-workspace-common.sh
source "${SCRIPT_DIR}/../lib/excalidraw-workspace-common.sh"
# shellcheck source=scripts/lib/docker-command-common.sh
source "${SCRIPT_DIR}/../lib/docker-command-common.sh"

ACTION="${1:-status}"
shift || true
LOG_DIR="${LOG_DIR:-${TMPDIR:-/tmp}}"
while [[ $# -gt 0 ]]; do
	case "$1" in
	--results)
		RESULTS_FILE="$2"
		shift 2
		;;
	--log-dir)
		LOG_DIR="$2"
		shift 2
		;;
	*)
		shift
		;;
	esac
done

CANVAS_IMAGE="${EXCALIDRAW_CANVAS_IMAGE:-ghcr.io/yctimlin/mcp_excalidraw-canvas:latest}"
MCP_IMAGE="${EXCALIDRAW_MCP_IMAGE:-ghcr.io/yctimlin/mcp_excalidraw:latest}"
CANVAS_NAME="${EXCALIDRAW_CANVAS_NAME:-mcp-excalidraw-canvas}"
CANVAS_PORT="${EXCALIDRAW_CANVAS_PORT:-3210}"
CANVAS_URL="${EXCALIDRAW_CANVAS_URL:-http://127.0.0.1:${CANVAS_PORT}}"
WORKSPACE_HOST="$(resolve_excalidraw_workspace_host)"
WORKSPACE_CONTAINER="${EXCALIDRAW_EXPORT_DIR:-/workspace/excalidraw}"
EXCALIDRAW_DOCKER_CMD=""
if resolve_excalidraw_docker_bin >/dev/null 2>/dev/null; then
	EXCALIDRAW_DOCKER_CMD="${EXCALIDRAW_DOCKER_BIN_RESOLVED}"
fi

docker_cmd() {
	[[ -n "${EXCALIDRAW_DOCKER_CMD}" ]] || return 1
	printf '%s\n' "${EXCALIDRAW_DOCKER_CMD}"
}

docker_available() {
	[[ -n "${EXCALIDRAW_DOCKER_CMD}" ]]
}

docker_resolution_message() {
	printf '%s\n' "${EXCALIDRAW_DOCKER_RESOLUTION_ERROR:-No responsive Docker command found; open Docker Desktop or verify WSL integration.}"
}

canvas_running() {
	local d
	d="$(docker_cmd)" || return 1
	"$d" ps --filter "name=^/${CANVAS_NAME}$" --filter "status=running" --format '{{.Names}}' 2>/dev/null | grep -Fxq "$CANVAS_NAME"
}

canvas_port_mapping() {
	local d
	d="$(docker_cmd)" || return 1
	local mapping
	mapping="$("$d" port "$CANVAS_NAME" 3000/tcp 2>/dev/null || true)"
	if [[ -n "$mapping" ]]; then
		printf '%s\n' "$mapping"
		return 0
	fi
	"$d" inspect "$CANVAS_NAME" --format '{{json .HostConfig.PortBindings}}' 2>/dev/null || true
}

mapping_is_expected() {
	local mapping="$1"
	[[ -n "$mapping" && ("$mapping" == *":${CANVAS_PORT}" || "$mapping" == *"\"HostPort\":\"${CANVAS_PORT}\""*) ]]
}

port_in_use() {
	case "${EXCALIDRAW_SKIP_PORT_CHECK:-}" in
	1 | true | TRUE | yes | YES | on | ON) return 1 ;;
	esac
	if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :${CANVAS_PORT} )" 2>/dev/null | grep -q ":${CANVAS_PORT}"; then
		return 0
	fi
	if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"${CANVAS_PORT}" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
		return 0
	fi
	if command -v timeout >/dev/null 2>&1 && timeout 1 bash -c "</dev/tcp/127.0.0.1/${CANVAS_PORT}" >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

case "$ACTION" in
start)
	d="$(docker_cmd)" || {
		echo "WARN   $(docker_resolution_message)"
		exit 1
	}
	if canvas_running; then
		mapping="$(canvas_port_mapping)"
		if ! mapping_is_expected "$mapping"; then
			echo "WARN   Excalidraw canvas is running with unexpected port mapping: ${mapping}"
			echo "       Expected host port ${CANVAS_PORT} -> container port 3000. Stop/remove the stale container, then run: make excalidraw-start"
			exit 1
		fi
		echo "Excalidraw canvas already running: ${CANVAS_URL}"
		exit 0
	fi
	if "$d" ps -a --filter "name=^/${CANVAS_NAME}$" --format '{{.Names}}' 2>/dev/null | grep -Fxq "$CANVAS_NAME"; then
		mapping="$(canvas_port_mapping)"
		if ! mapping_is_expected "$mapping"; then
			echo "WARN   Existing Excalidraw canvas container uses unexpected port mapping: ${mapping}"
			echo "       Expected host port ${CANVAS_PORT} -> container port 3000. Remove/recreate the stale container or run: docker rm ${CANVAS_NAME}"
			exit 1
		fi
		"$d" start "$CANVAS_NAME" >/dev/null
	else
		if port_in_use; then
			echo "WARN   Port ${CANVAS_PORT} is already in use. Excalidraw canvas is reserved for ${CANVAS_URL}."
			echo "       Stop the process using ${CANVAS_PORT}, then run: make excalidraw-start"
			exit 1
		fi
		if ! "$d" run -d -p "${CANVAS_PORT}:3000" --name "$CANVAS_NAME" "$CANVAS_IMAGE" >/dev/null; then
			echo "WARN   Could not start Excalidraw canvas on ${CANVAS_URL} (Docker port mapping ${CANVAS_PORT}:3000)."
			echo "       Check whether port ${CANVAS_PORT} is occupied, then run: make excalidraw-status"
			exit 1
		fi
	fi
	echo "Excalidraw canvas running: ${CANVAS_URL}"
	;;
stop)
	d="$(docker_cmd)" || {
		echo "WARN   $(docker_resolution_message)"
		exit 0
	}
	if canvas_running; then
		"$d" stop "$CANVAS_NAME" >/dev/null
		echo "Excalidraw canvas stopped"
	else
		echo "Excalidraw canvas already stopped"
	fi
	;;
status)
	if ! d="$(docker_cmd)"; then
		echo "WARN   $(docker_resolution_message)"
		echo "WARN   Docker does not respond; open Docker Desktop or verify WSL integration"
		exit 0
	fi
	echo "INFO   Docker command: $d"
	if [[ -n "${EXCALIDRAW_DOCKER_RESOLUTION_NOTE}" ]]; then
		echo "INFO   ${EXCALIDRAW_DOCKER_RESOLUTION_NOTE}"
	fi
	echo "OK     Docker responds"
	if canvas_running; then
		mapping="$(canvas_port_mapping)"
		if mapping_is_expected "$mapping"; then
			echo "OK     Canvas running: ${CANVAS_URL}"
		else
			echo "WARN   Canvas running with unexpected port mapping: ${mapping}"
			echo "INFO   Expected URL: ${CANVAS_URL} (Docker mapping ${CANVAS_PORT}:3000)"
		fi
	else
		echo "INFO   Canvas not running. Start with: make excalidraw-start (${CANVAS_URL})"
	fi
	echo "INFO   Authorized Excalidraw workspace: ${WORKSPACE_HOST} -> ${WORKSPACE_CONTAINER}"
	;;
update)
	if ! d="$(docker_cmd)"; then
		if [[ "${EXCALIDRAW_DOCKER_EXPLICIT_FAILED}" -eq 1 ]]; then
			msg="$(docker_resolution_message)"
			warn "$msg"
			if [[ -n "${RESULTS_FILE:-}" ]]; then
				result_fail "WSL" "Excalidraw Docker" "$msg"
			fi
			exit 1
		fi
		msg="No responsive Docker command found; Excalidraw images were not updated"
		note="Open Docker Desktop or verify WSL integration, then run 'make excalidraw-update' if you need this optional component"
		skip "$msg"
		info "$(docker_resolution_message)"
		info "$note"
		if [[ -n "${RESULTS_FILE:-}" ]]; then
			result_skip "WSL" "Excalidraw Docker" "$msg"
			result_info "WSL" "Excalidraw Docker" "$(docker_resolution_message)"
			result_info "WSL" "Excalidraw Docker" "$note"
		fi
		exit 0
	fi
	if ! check_docker_credentials_for_images "$CANVAS_IMAGE" "$MCP_IMAGE"; then
		msg="${DOCKER_CREDENTIALS_LAST_MESSAGE}"
		warn "$msg"
		if [[ -n "${RESULTS_FILE:-}" ]]; then
			result_fail "WSL" "Excalidraw Docker credentials" "$msg"
		fi
		exit 1
	fi
	mkdir -p "$LOG_DIR"
	run_step "WSL" "Excalidraw canvas image" "${LOG_DIR}/excalidraw-canvas-pull.log" "$d" pull "$CANVAS_IMAGE"
	run_step "WSL" "Excalidraw MCP image" "${LOG_DIR}/excalidraw-mcp-pull.log" "$d" pull "$MCP_IMAGE"
	;;
*)
	echo "Usage: $0 {start|stop|status|update}" >&2
	exit 2
	;;
esac
