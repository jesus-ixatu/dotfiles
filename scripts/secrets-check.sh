#!/usr/bin/env bash
# Read-only SOPS/Age/Chezmoi secrets readiness diagnostic.
# Never decrypts secrets to stdout and never writes generated secret surfaces.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_DIR="${SECRETS_CHECK_SOURCE_DIR:-${DOTFILES_ROOT}}"
SECRETS_YAML="${SOURCE_DIR}/secrets.sops.yaml"
AGE_KEY="${HOME}/.config/sops/age/keys.txt"

ok=0
warn=0
fail=0
strict=0

is_truthy() {
	case "${1:-}" in
	1 | true | TRUE | yes | YES | on | ON) return 0 ;;
	*) return 1 ;;
	esac
}

if is_truthy "${STRICT:-}" || is_truthy "${MCP_SECRETS_STRICT:-}"; then
	strict=1
fi

bump() {
	case "$1" in
	OK) ok=$((ok + 1)) ;;
	WARN) warn=$((warn + 1)) ;;
	FAIL) fail=$((fail + 1)) ;;
	esac
}

line() {
	local state="$1"
	local msg="$2"
	printf '%-5s %s\n' "${state}" "${msg}"
	bump "${state}"
}

critical() {
	local msg="$1"
	if [[ "${strict}" -eq 1 ]]; then
		line FAIL "${msg}"
	else
		line WARN "${msg}"
	fi
}

mode_string() {
	local mode="${1}"
	local symbolic="${mode}"
	case "${mode}" in
	600) symbolic="-rw-------" ;;
	640) symbolic="-rw-r-----" ;;
	644) symbolic="-rw-r--r--" ;;
	444) symbolic="-r--r--r--" ;;
	esac
	printf '%s' "${symbolic}"
}

file_mode() {
	local path="$1"
	stat -c '%a' "${path}" 2>/dev/null || stat -f '%Lp' "${path}" 2>/dev/null || true
}

check_permissions_600() {
	local path="$1"
	local mode
	mode="$(file_mode "${path}")"
	if [[ "${mode}" == "600" ]]; then
		line OK "${path} permissions are 600"
	elif [[ -n "${mode}" ]]; then
		line WARN "${path} permissions are $(mode_string "${mode}"); expected 600"
	else
		line WARN "${path} permissions could not be read; expected 600"
	fi
}

check_surface_file() {
	local path="$1"
	if [[ -f "${path}" ]]; then
		line OK "${path} exists"
		check_permissions_600 "${path}"
	else
		line WARN "${path} missing; run chezmoi apply to generate it"
	fi
}

check_codex_adapter() {
	local path="${HOME}/.secrets/codex.env"
	local expected="${HOME}/.config/mcp-secrets.env"
	local target=""

	if [[ -L "${path}" ]]; then
		target="$(readlink "${path}" 2>/dev/null || true)"
		if [[ "${target}" == "${expected}" ]]; then
			line OK "${path} symlink points to ${expected}"
		else
			line WARN "${path} symlink points to ${target:-<unreadable>}; expected ${expected}"
		fi
	elif [[ -e "${path}" ]]; then
		line WARN "${path} exists but is not the expected symlink to ${expected}"
		[[ -f "${path}" ]] && check_permissions_600 "${path}"
	else
		line WARN "${path} missing; run chezmoi apply to generate it"
	fi
}

echo "Secret readiness diagnostic (read-only)"
echo ""

if [[ -f "${AGE_KEY}" ]]; then
	line OK "Age key exists at ${AGE_KEY}"
else
	critical "Age key missing at ${AGE_KEY}"
fi

have_sops=0
if command -v sops >/dev/null 2>&1; then
	have_sops=1
	line OK "sops available"
else
	critical "sops not in PATH"
fi

have_secrets_file=0
appears_encrypted=0
if [[ -f "${SECRETS_YAML}" ]]; then
	have_secrets_file=1
	line OK "secrets.sops.yaml present"
	if grep -q 'ENC\[' "${SECRETS_YAML}" 2>/dev/null; then
		appears_encrypted=1
		line OK "secrets.sops.yaml appears encrypted"
	else
		critical "secrets.sops.yaml present but does not contain SOPS ENC[...] markers"
	fi
else
	critical "secrets.sops.yaml missing at ${SECRETS_YAML}"
fi

if [[ "${have_sops}" -eq 1 && "${have_secrets_file}" -eq 1 && "${appears_encrypted}" -eq 1 ]]; then
	if sops --decrypt "${SECRETS_YAML}" >/dev/null 2>&1; then
		line OK "SOPS decrypt works"
	else
		critical "SOPS decrypt failed for secrets.sops.yaml"
	fi
elif [[ "${have_secrets_file}" -eq 1 && "${appears_encrypted}" -eq 1 ]]; then
	critical "SOPS decrypt not checked because sops is unavailable"
fi

if command -v yq >/dev/null 2>&1; then
	line OK "YAML parser available: yq"
elif python3 -c "import yaml" >/dev/null 2>&1; then
	line OK "YAML parser available: python3+PyYAML"
else
	critical "YAML parser missing: install yq or python3+PyYAML"
fi

echo ""
echo "Generated surfaces"
check_surface_file "${HOME}/.config/mcp-secrets.env"
check_surface_file "${HOME}/.config/store-etl/secrets.env"
check_codex_adapter
check_surface_file "${HOME}/.secrets/store-etl/minio_access_key"
check_surface_file "${HOME}/.secrets/store-etl/minio_secret_key"

echo ""
printf 'Summary: OK=%s WARN=%s FAIL=%s\n' "${ok}" "${warn}" "${fail}"

if [[ "${fail}" -gt 0 ]]; then
	exit 1
fi

exit 0
