#!/usr/bin/env bash
# Shared Excalidraw workspace path resolution for MCP checks and update helpers.

LEGACY_EXCALIDRAW_WORKSPACE_HOST="/mnt/c/Users/jesus/Documents/vault_trabajo/excalidraw"

resolve_excalidraw_workspace_host() {
	if [[ -n "${EXCALIDRAW_WORKSPACE_HOST:-}" ]]; then
		printf '%s\n' "${EXCALIDRAW_WORKSPACE_HOST}"
		return 0
	fi

	local chezmoi_config="${CHEZMOI_CONFIG:-${HOME}/.config/chezmoi/chezmoi.toml}"
	local resolved=""

	if [[ -f "${chezmoi_config}" ]] && command -v python3 >/dev/null 2>&1; then
		if resolved="$(
			python3 - "${chezmoi_config}" <<'PY' 2>/dev/null
import os
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib  # type: ignore
    except ModuleNotFoundError:
        raise SystemExit(1)

path = Path(sys.argv[1])
try:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(1)

ai = ((data.get("data") or {}).get("ai") or {})
if not isinstance(ai, dict):
    raise SystemExit(0)

workspace = ai.get("excalidraw_workspace_host")
if isinstance(workspace, str) and workspace.strip():
    print(workspace)
    raise SystemExit(0)

vault = ai.get("obsidian_vault_path")
if isinstance(vault, str) and vault.strip():
    print(os.path.join(vault, "excalidraw"))
PY
		)"; then
			if [[ -n "${resolved}" ]]; then
				printf '%s\n' "${resolved}"
				return 0
			fi
		fi
	fi

	printf '%s\n' "${LEGACY_EXCALIDRAW_WORKSPACE_HOST}"
}

resolve_excalidraw_vault_root() {
	local workspace_host="${1:-}"
	if [[ -z "${workspace_host}" ]]; then
		workspace_host="$(resolve_excalidraw_workspace_host)"
	fi

	local root="${workspace_host%/*}"
	if [[ -z "${root}" || "${root}" == "${workspace_host}" ]]; then
		root="."
	fi
	printf '%s\n' "${root}"
}
