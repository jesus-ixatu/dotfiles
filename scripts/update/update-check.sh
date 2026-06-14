#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${DOTFILES_DIR:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
# shellcheck source=scripts/update/lib/environment.sh
source "${SCRIPT_DIR}/lib/environment.sh"
# shellcheck source=scripts/update/lib/node_runtime.sh
source "${SCRIPT_DIR}/lib/node_runtime.sh"
# shellcheck source=scripts/update/lib/docker_desktop_credentials.sh
source "${SCRIPT_DIR}/lib/docker_desktop_credentials.sh"
# shellcheck source=scripts/lib/docker-command-common.sh
source "${SCRIPT_DIR}/../lib/docker-command-common.sh"

status() {
	printf '%-6s %s\n' "$1" "$2"
}

echo "==> Dotfiles update readiness"
if is_wsl; then
	status OK "WSL detected"
else
	status WARN "Not running under WSL; make update will skip Windows tab orchestration"
fi
for cmd in make bash; do
	if command -v "$cmd" >/dev/null 2>&1; then status OK "$cmd in PATH"; else status WARN "$cmd missing"; fi
done
for cmd in wt.exe powershell.exe wslpath; do
	if command -v "$cmd" >/dev/null 2>&1; then status OK "$cmd available from WSL"; else status WARN "$cmd unavailable from WSL"; fi
done
while IFS=$'\t' read -r state message; do
	[[ -n "$state" && -n "$message" ]] || continue
	status "$state" "$message"
done < <(node_runtime_diagnostic_effective)
docker_cmd=""
docker_note=""
docker_error=""
if resolve_responsive_docker_bin docker_cmd docker_note docker_error; then
	status INFO "Docker command: ${docker_cmd}"
	[[ -z "${docker_note}" ]] || status INFO "${docker_note}"
	status OK "Docker responds"
	if check_docker_credentials_for_images \
		"ghcr.io/yctimlin/mcp_excalidraw-canvas:latest" \
		"ghcr.io/yctimlin/mcp_excalidraw:latest"; then
		status OK "${DOCKER_CREDENTIALS_LAST_MESSAGE}"
	else
		status WARN "${DOCKER_CREDENTIALS_LAST_MESSAGE}"
	fi
else
	status WARN "${docker_error:-No responsive Docker command found; open Docker Desktop or verify WSL integration.}"
	status WARN "Docker credential helper check deferred until Docker is available"
fi
if [[ -f "${DOTFILES_ROOT}/ai/assets/mcps/MANIFEST.yaml" ]]; then
	status OK "MCP manifest present"
fi
echo "==> Checkout AI surface"
if DOTFILES_DIR="${DOTFILES_ROOT}" "${DOTFILES_ROOT}/scripts/diagnose-checkout-ai-surface.sh"; then
	status OK "Checkout AI runtime surface is clean"
else
	status WARN "Checkout AI runtime surface needs manual cleanup; .claude/ belongs in HOME runtime, not the checkout"
fi
echo "==> GitHub identity"
if "${DOTFILES_ROOT}/scripts/github-identity-check.sh" --offline --warn-only; then
	status OK "GitHub identity diagnostic completed"
else
	status WARN "GitHub identity diagnostic reported issues"
fi
echo "==> Excalidraw"
"${SCRIPT_DIR}/update-excalidraw.sh" status || true
