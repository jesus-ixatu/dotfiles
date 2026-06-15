#!/usr/bin/env bats
# scripts/secrets-check.sh — read-only SOPS/Age/Chezmoi secrets readiness.

load '../helpers/common'

setup() {
	setup_temp_dir
	DOTFILES_DIR="$(get_dotfiles_dir)"
	SCRIPT="${DOTFILES_DIR}/scripts/secrets-check.sh"
	TEST_HOME="${TEST_TEMP_DIR}/home"
	MOCK_SOURCE="${TEST_TEMP_DIR}/source"
	MOCK_BIN="${TEST_TEMP_DIR}/bin"
	mkdir -p "${TEST_HOME}" "${MOCK_SOURCE}" "${MOCK_BIN}"
	export HOME="${TEST_HOME}"
	export SECRETS_CHECK_SOURCE_DIR="${MOCK_SOURCE}"
	SECRET_VALUE="ghp_FAKE000000000000000000000000000000"
}

teardown() {
	teardown_temp_dir
}

write_encrypted_secrets() {
	cat >"${MOCK_SOURCE}/secrets.sops.yaml" <<'EOF'
mcp:
    github_personal_access_token: ENC[AES256_GCM,data=fake,type:str]
EOF
}

write_plain_secrets() {
	cat >"${MOCK_SOURCE}/secrets.sops.yaml" <<'EOF'
mcp:
    github_personal_access_token: plaintext
EOF
}

write_age_key() {
	mkdir -p "${HOME}/.config/sops/age"
	printf 'fake-age-key-placeholder\n' >"${HOME}/.config/sops/age/keys.txt"
	chmod 600 "${HOME}/.config/sops/age/keys.txt"
}

write_successful_sops() {
	cat >"${MOCK_BIN}/sops" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "--decrypt" ]]; then
	printf '%s\n' "${SECRET_VALUE}"
	exit 0
fi
echo "sops 99.9.9"
EOF
	chmod +x "${MOCK_BIN}/sops"
}

write_failing_sops() {
	cat >"${MOCK_BIN}/sops" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--decrypt" ]]; then
	echo "decrypt failed without secret values" >&2
	exit 1
fi
echo "sops 99.9.9"
EOF
	chmod +x "${MOCK_BIN}/sops"
}

write_successful_python() {
	cat >"${MOCK_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-c" && "$2" == "import yaml" ]]; then
	exit 0
fi
exec /usr/bin/python3 "$@"
EOF
	chmod +x "${MOCK_BIN}/python3"
}

write_failing_python() {
	cat >"${MOCK_BIN}/python3" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-c" && "$2" == "import yaml" ]]; then
	exit 1
fi
exec /usr/bin/python3 "$@"
EOF
	chmod +x "${MOCK_BIN}/python3"
}

write_generated_surfaces() {
	mkdir -p "${HOME}/.config/store-etl" "${HOME}/.secrets/store-etl"
	printf 'export GITHUB_PERSONAL_ACCESS_TOKEN="<redacted fixture>"\n' >"${HOME}/.config/mcp-secrets.env"
	printf 'export GITHUB_PERSONAL_ACCESS_TOKEN="<redacted fixture>"\n' >"${HOME}/.config/store-etl/secrets.env"
	printf 'fake-minio-access\n' >"${HOME}/.secrets/store-etl/minio_access_key"
	printf 'fake-minio-secret\n' >"${HOME}/.secrets/store-etl/minio_secret_key"
	chmod 600 \
		"${HOME}/.config/mcp-secrets.env" \
		"${HOME}/.config/store-etl/secrets.env" \
		"${HOME}/.secrets/store-etl/minio_access_key" \
		"${HOME}/.secrets/store-etl/minio_secret_key"
	ln -s "${HOME}/.config/mcp-secrets.env" "${HOME}/.secrets/codex.env"
}

run_check() {
	run env PATH="${MOCK_BIN}:/usr/bin:/bin" HOME="${HOME}" SECRETS_CHECK_SOURCE_DIR="${SECRETS_CHECK_SOURCE_DIR}" "$@" "${SCRIPT}"
}

@test "happy path exits 0 without printing decrypted secret values" {
	write_age_key
	write_encrypted_secrets
	write_successful_sops
	write_successful_python
	write_generated_surfaces

	run_check
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"Secret readiness diagnostic (read-only)"* ]]
	[[ "${output}" == *"OK    Age key exists"* ]]
	[[ "${output}" == *"OK    sops available"* ]]
	[[ "${output}" == *"OK    SOPS decrypt works"* ]]
	[[ "${output}" == *"OK    YAML parser available: python3+PyYAML"* ]]
	[[ "${output}" == *"OK    ${HOME}/.secrets/codex.env symlink points to ${HOME}/.config/mcp-secrets.env"* ]]
	[[ "${output}" == *"Summary: OK="* ]]
	[[ "${output}" != *"${SECRET_VALUE}"* ]]
}

@test "missing Age key warns by default and fails in strict mode" {
	write_encrypted_secrets
	write_successful_sops
	write_successful_python

	run_check
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"WARN  Age key missing"* ]]

	run_check env STRICT=1
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"FAIL  Age key missing"* ]]
}

@test "missing sops warns by default and fails in strict mode" {
	write_age_key
	write_encrypted_secrets
	write_successful_python

	run_check
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"WARN  sops not in PATH"* ]]

	run_check env STRICT=1
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"FAIL  sops not in PATH"* ]]
}

@test "sops decrypt failure is warning by default and fail in strict mode" {
	write_age_key
	write_encrypted_secrets
	write_failing_sops
	write_successful_python

	run_check
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"WARN  SOPS decrypt failed"* ]]
	[[ "${output}" != *"${SECRET_VALUE}"* ]]

	run_check env MCP_SECRETS_STRICT=1
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"FAIL  SOPS decrypt failed"* ]]
}

@test "unencrypted secrets file is reported clearly" {
	write_age_key
	write_plain_secrets
	write_successful_sops
	write_successful_python

	run_check
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"WARN  secrets.sops.yaml present but does not contain SOPS ENC[...] markers"* ]]

	run_check env STRICT=1
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"FAIL  secrets.sops.yaml present but does not contain SOPS ENC[...] markers"* ]]
}

@test "missing YAML parser is warning by default and fail in strict mode" {
	write_age_key
	write_encrypted_secrets
	write_successful_sops
	write_failing_python

	run_check
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"WARN  YAML parser missing"* ]]

	run_check env STRICT=1
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"FAIL  YAML parser missing"* ]]
}

@test "open permissions warn and are not changed" {
	write_age_key
	write_encrypted_secrets
	write_successful_sops
	write_successful_python
	write_generated_surfaces
	chmod 644 "${HOME}/.config/mcp-secrets.env"
	chmod 444 "${HOME}/.secrets/store-etl/minio_access_key"

	run_check
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"WARN  ${HOME}/.config/mcp-secrets.env permissions are -rw-r--r--; expected 600"* ]]
	[[ "${output}" == *"WARN  ${HOME}/.secrets/store-etl/minio_access_key permissions are -r--r--r--; expected 600"* ]]
	[[ "$(stat -c '%a' "${HOME}/.config/mcp-secrets.env")" == "644" ]]
	[[ "$(stat -c '%a' "${HOME}/.secrets/store-etl/minio_access_key")" == "444" ]]
}

@test "missing generated surfaces warn but exit 0 by default" {
	write_age_key
	write_encrypted_secrets
	write_successful_sops
	write_successful_python

	run_check
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"WARN  ${HOME}/.config/mcp-secrets.env missing; run chezmoi apply to generate it"* ]]
	[[ "${output}" == *"WARN  ${HOME}/.config/store-etl/secrets.env missing; run chezmoi apply to generate it"* ]]
	[[ "${output}" == *"WARN  ${HOME}/.secrets/codex.env missing; run chezmoi apply to generate it"* ]]
	[[ "${output}" == *"WARN  ${HOME}/.secrets/store-etl/minio_access_key missing; run chezmoi apply to generate it"* ]]
	[[ "${output}" == *"WARN  ${HOME}/.secrets/store-etl/minio_secret_key missing; run chezmoi apply to generate it"* ]]
}
