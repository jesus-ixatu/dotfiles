#!/usr/bin/env bash
# Shared Docker command resolution for Excalidraw operations.

EXCALIDRAW_DOCKER_BIN_RESOLVED=""
EXCALIDRAW_DOCKER_RESOLUTION_NOTE=""
EXCALIDRAW_DOCKER_RESOLUTION_ERROR=""
EXCALIDRAW_DOCKER_EXPLICIT_FAILED=0

docker_command_responds() {
	local cmd="$1"
	[[ -n "${cmd}" ]] || return 1
	command -v -- "${cmd}" >/dev/null 2>&1 || return 1
	"${cmd}" info >/dev/null 2>&1
}

resolve_excalidraw_docker_bin() {
	EXCALIDRAW_DOCKER_BIN_RESOLVED=""
	EXCALIDRAW_DOCKER_RESOLUTION_NOTE=""
	EXCALIDRAW_DOCKER_RESOLUTION_ERROR=""
	EXCALIDRAW_DOCKER_EXPLICIT_FAILED=0

	if [[ -n "${EXCALIDRAW_DOCKER_BIN:-}" ]]; then
		if docker_command_responds "${EXCALIDRAW_DOCKER_BIN}"; then
			EXCALIDRAW_DOCKER_BIN_RESOLVED="${EXCALIDRAW_DOCKER_BIN}"
			printf '%s\n' "${EXCALIDRAW_DOCKER_BIN_RESOLVED}"
			return 0
		fi
		# shellcheck disable=SC2034 # Read by callers after sourcing this helper.
		EXCALIDRAW_DOCKER_EXPLICIT_FAILED=1
		EXCALIDRAW_DOCKER_RESOLUTION_ERROR="EXCALIDRAW_DOCKER_BIN does not respond: ${EXCALIDRAW_DOCKER_BIN}"
		printf '%s\n' "${EXCALIDRAW_DOCKER_RESOLUTION_ERROR}" >&2
		return 1
	fi

	local docker_exists=0
	local docker_failed=0
	if command -v docker >/dev/null 2>&1; then
		docker_exists=1
		if docker_command_responds docker; then
			EXCALIDRAW_DOCKER_BIN_RESOLVED="docker"
			printf '%s\n' "${EXCALIDRAW_DOCKER_BIN_RESOLVED}"
			return 0
		fi
		docker_failed=1
	fi

	if docker_command_responds docker.exe; then
		EXCALIDRAW_DOCKER_BIN_RESOLVED="docker.exe"
		if [[ "${docker_exists}" -eq 1 && "${docker_failed}" -eq 1 ]]; then
			# shellcheck disable=SC2034 # Read by callers after sourcing this helper.
			EXCALIDRAW_DOCKER_RESOLUTION_NOTE="docker exists but does not respond; using docker.exe"
		fi
		printf '%s\n' "${EXCALIDRAW_DOCKER_BIN_RESOLVED}"
		return 0
	fi

	if [[ "${docker_exists}" -eq 1 && "${docker_failed}" -eq 1 ]]; then
		EXCALIDRAW_DOCKER_RESOLUTION_ERROR="No responsive Docker command found; docker exists but does not respond and docker.exe is unavailable or not responding. Open Docker Desktop or verify WSL integration."
	else
		EXCALIDRAW_DOCKER_RESOLUTION_ERROR="No responsive Docker command found; open Docker Desktop or verify WSL integration."
	fi
	printf '%s\n' "${EXCALIDRAW_DOCKER_RESOLUTION_ERROR}" >&2
	return 1
}
