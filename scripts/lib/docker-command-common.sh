#!/usr/bin/env bash
# Shared Docker command resolution for diagnostics and Excalidraw operations.

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

resolve_responsive_docker_bin() {
	local result_var="${1:-}"
	local note_var="${2:-}"
	local error_var="${3:-}"
	local docker_resolved=""
	local docker_note=""
	local docker_error=""

	[[ -z "${result_var}" ]] || printf -v "${result_var}" '%s' ""
	[[ -z "${note_var}" ]] || printf -v "${note_var}" '%s' ""
	[[ -z "${error_var}" ]] || printf -v "${error_var}" '%s' ""

	local docker_exists=0
	local docker_failed=0
	if command -v docker >/dev/null 2>&1; then
		docker_exists=1
		if docker_command_responds docker; then
			docker_resolved="docker"
		else
			docker_failed=1
		fi
	fi

	if [[ -z "${docker_resolved}" ]] && docker_command_responds docker.exe; then
		docker_resolved="docker.exe"
		if [[ "${docker_exists}" -eq 1 && "${docker_failed}" -eq 1 ]]; then
			docker_note="docker exists but does not respond; using docker.exe"
		fi
	fi

	if [[ -n "${docker_resolved}" ]]; then
		if [[ -n "${result_var}" ]]; then
			printf -v "${result_var}" '%s' "${docker_resolved}"
		else
			printf '%s\n' "${docker_resolved}"
		fi
		[[ -z "${note_var}" ]] || printf -v "${note_var}" '%s' "${docker_note}"
		return 0
	fi

	if [[ "${docker_exists}" -eq 1 && "${docker_failed}" -eq 1 ]]; then
		docker_error="No responsive Docker command found; docker exists but does not respond and docker.exe is unavailable or not responding. Open Docker Desktop or verify WSL integration."
	else
		docker_error="No responsive Docker command found; open Docker Desktop or verify WSL integration."
	fi
	if [[ -n "${error_var}" ]]; then
		printf -v "${error_var}" '%s' "${docker_error}"
	else
		printf '%s\n' "${docker_error}" >&2
	fi
	return 1
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

	local resolved=""
	local note=""
	local error=""
	if resolve_responsive_docker_bin resolved note error; then
		EXCALIDRAW_DOCKER_BIN_RESOLVED="${resolved}"
		# shellcheck disable=SC2034 # Read by callers after sourcing this helper.
		EXCALIDRAW_DOCKER_RESOLUTION_NOTE="${note}"
		printf '%s\n' "${EXCALIDRAW_DOCKER_BIN_RESOLVED}"
		return 0
	fi

	EXCALIDRAW_DOCKER_RESOLUTION_ERROR="${error}"
	printf '%s\n' "${EXCALIDRAW_DOCKER_RESOLUTION_ERROR}" >&2
	return 1
}
