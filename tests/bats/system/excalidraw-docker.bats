#!/usr/bin/env bats

setup() {
	load '../helpers/common'
	DOTFILES_DIR="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
	DOCKER_HELPER="${DOTFILES_DIR}/scripts/lib/docker-command-common.sh"
	setup_temp_dir
	FAKE_BIN="${TEST_TEMP_DIR}/bin"
	mkdir -p "${FAKE_BIN}"
	DOCKER_LOG="${TEST_TEMP_DIR}/docker.log"
	export DOCKER_LOG
	DOCKER_CONFIG="${TEST_TEMP_DIR}/docker-config"
	export DOCKER_CONFIG
	mkdir -p "$DOCKER_CONFIG"
	for cmd in bash python3 mktemp rm dirname pwd mkdir grep tee date tr chmod; do
		ln -sf "$(command -v "$cmd")" "${FAKE_BIN}/${cmd}"
	done
	cat >"${FAKE_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$DOCKER_LOG"
case "$1" in
  info) exit 0 ;;
  version) exit 0 ;;
  ps)
    if [[ "$*" == *"--format"* ]]; then exit 0; fi
    exit 0
    ;;
	  port) exit 0 ;;
	  run|pull|stop|start) exit 0 ;;
  image) exit 1 ;;
  *) exit 0 ;;
esac
EOF
	chmod +x "${FAKE_BIN}/docker"
}

teardown() {
	teardown_temp_dir
}

@test "excalidraw docker resolver chooses docker when it responds" {
	run env PATH="${FAKE_BIN}:/usr/bin:/bin" bash -c 'source "$1"; resolve_excalidraw_docker_bin' _ "${DOCKER_HELPER}"
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == "docker" ]]
}

@test "excalidraw docker resolver falls back to docker.exe when docker does not respond" {
	local fallback_bin="${TEST_TEMP_DIR}/fallback-bin"
	mkdir -p "${fallback_bin}"
	cat >"${fallback_bin}/docker" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
	cat >"${fallback_bin}/docker.exe" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  info) exit 0 ;;
  ps) exit 0 ;;
  *) exit 0 ;;
esac
EOF
	chmod +x "${fallback_bin}/docker" "${fallback_bin}/docker.exe"
	run env PATH="${fallback_bin}:/usr/bin:/bin" bash -c 'source "$1"; resolve_excalidraw_docker_bin >/dev/null; printf "%s|%s\n" "$EXCALIDRAW_DOCKER_BIN_RESOLVED" "$EXCALIDRAW_DOCKER_RESOLUTION_NOTE"' _ "${DOCKER_HELPER}"
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == "docker.exe|docker exists but does not respond; using docker.exe" ]]

	run env PATH="${fallback_bin}:/usr/bin:/bin" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" status
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"Docker command: docker.exe"* ]]
	[[ "${output}" == *"docker exists but does not respond; using docker.exe"* ]]
}

@test "excalidraw docker resolver honors functional EXCALIDRAW_DOCKER_BIN override" {
	local explicit_bin="${TEST_TEMP_DIR}/explicit docker"
	cat >"${explicit_bin}" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  info) exit 0 ;;
  *) exit 0 ;;
esac
EOF
	chmod +x "${explicit_bin}"
	run env PATH="${FAKE_BIN}:/usr/bin:/bin" EXCALIDRAW_DOCKER_BIN="${explicit_bin}" bash -c 'source "$1"; resolve_excalidraw_docker_bin' _ "${DOCKER_HELPER}"
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == "${explicit_bin}" ]]
}

@test "excalidraw docker resolver fails broken EXCALIDRAW_DOCKER_BIN without fallback" {
	local explicit_bin="${TEST_TEMP_DIR}/broken-docker"
	cat >"${explicit_bin}" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
	chmod +x "${explicit_bin}"
	run env PATH="${FAKE_BIN}:/usr/bin:/bin" EXCALIDRAW_DOCKER_BIN="${explicit_bin}" bash -c 'source "$1"; resolve_excalidraw_docker_bin' _ "${DOCKER_HELPER}"
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"EXCALIDRAW_DOCKER_BIN does not respond: ${explicit_bin}"* ]]
	[[ "${output}" != *"docker.exe"* ]]

	run env PATH="${FAKE_BIN}:/usr/bin:/bin" EXCALIDRAW_DOCKER_BIN="${explicit_bin}" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" update
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"EXCALIDRAW_DOCKER_BIN does not respond: ${explicit_bin}"* ]]
	assert_file_not_contains "${DOCKER_LOG}" 'pull ghcr.io/yctimlin/mcp_excalidraw'
}

@test "excalidraw docker resolver fails clearly when no Docker command responds" {
	local empty_path="${TEST_TEMP_DIR}/empty-docker-path"
	mkdir -p "${empty_path}"
	local bash_abs
	bash_abs="$(command -v bash)"
	run env PATH="${empty_path}" "${bash_abs}" -c 'source "$1"; resolve_excalidraw_docker_bin' _ "${DOCKER_HELPER}"
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"No responsive Docker command found"* ]]
}

@test "excalidraw update pulls upstream Docker images" {
	run env PATH="${FAKE_BIN}:/usr/bin:/bin" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" update
	[[ "${status}" -eq 0 ]]
	grep -q 'pull ghcr.io/yctimlin/mcp_excalidraw-canvas:latest' "${DOCKER_LOG}"
	grep -q 'pull ghcr.io/yctimlin/mcp_excalidraw:latest' "${DOCKER_LOG}"
	assert_file_not_contains "${DOCKER_LOG}" 'run -d'
}

@test "excalidraw start uses canvas container and is idempotent-compatible" {
	run env PATH="${FAKE_BIN}:/usr/bin:/bin" EXCALIDRAW_SKIP_PORT_CHECK=1 bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" start
	[[ "${status}" -eq 0 ]]
	grep -q 'run -d -p 3210:3000 --name mcp-excalidraw-canvas ghcr.io/yctimlin/mcp_excalidraw-canvas:latest' "${DOCKER_LOG}"
	[[ "${output}" == *"http://127.0.0.1:3210"* ]]
}

@test "excalidraw status reports dedicated canvas port" {
	run env PATH="${FAKE_BIN}:/usr/bin:/bin" EXCALIDRAW_WORKSPACE_HOST="/tmp/My Excalidraw Workspace" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" status
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"http://127.0.0.1:3210"* ]]
	[[ "${output}" == *"/tmp/My Excalidraw Workspace -> /workspace/excalidraw"* ]]
}

@test "excalidraw status resolves workspace from Chezmoi config with spaces" {
	local cfg workspace
	cfg="${TEST_TEMP_DIR}/chezmoi.toml"
	workspace="${TEST_TEMP_DIR}/Vault With Spaces/excalidraw"
	cat >"${cfg}" <<TOML
[data.ai]
excalidraw_workspace_host = "${workspace}"
TOML
	run env PATH="${FAKE_BIN}:/usr/bin:/bin" CHEZMOI_CONFIG="${cfg}" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" status
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"${workspace} -> /workspace/excalidraw"* ]]
}

@test "excalidraw update reports Docker Desktop down as SKIP and not incident" {
	local results_file="${TEST_TEMP_DIR}/results.tsv"
	local down_bin="${TEST_TEMP_DIR}/down-bin"
	mkdir -p "$down_bin"
	cat >"${down_bin}/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  info) exit 1 ;;
  *) exit 0 ;;
esac
EOF
	chmod +x "${down_bin}/docker"
	run env PATH="${down_bin}:/usr/bin:/bin" RESULTS_FILE="$results_file" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" update --results "$results_file"
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"SKIP"* ]]
	[[ "${output}" == *"No responsive Docker command found"* ]]
	[[ "${output}" == *"make excalidraw-update"* ]]
	grep -q $'SKIP\tWSL\tExcalidraw Docker\tNo responsive Docker command found; Excalidraw images were not updated' "$results_file"
	grep -q $'INFO\tWSL\tExcalidraw Docker\tOpen Docker Desktop or verify WSL integration' "$results_file"
	run bash -c "source '${DOTFILES_DIR}/scripts/update/lib/results.sh'; result_has_incidents '$results_file'"
	[[ "${status}" -ne 0 ]]
}

@test "excalidraw update preserves daemon-down diagnostic before credential checks" {
	local results_file="${TEST_TEMP_DIR}/results-daemon.tsv"
	local down_bin="${TEST_TEMP_DIR}/down-bin-with-creds"
	mkdir -p "$down_bin"
	cat >"${DOCKER_CONFIG}/config.json" <<'EOF'
{"credsStore":"desktop.exe"}
EOF
	cat >"${down_bin}/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  info) exit 1 ;;
  pull) echo "pull should not run" >> "$DOCKER_LOG"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
	chmod +x "${down_bin}/docker"
	run env PATH="${down_bin}:/usr/bin:/bin" DOTFILES_FORCE_WSL=1 RESULTS_FILE="$results_file" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" update --results "$results_file"
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"No responsive Docker command found"* ]]
	assert_file_not_contains "${DOCKER_LOG}" 'pull should not run'
	grep -q $'SKIP\tWSL\tExcalidraw Docker\tNo responsive Docker command found; Excalidraw images were not updated' "$results_file"
}

@test "excalidraw update fails before pulls when required helper is absent" {
	local results_file="${TEST_TEMP_DIR}/results-creds.tsv"
	cat >"${DOCKER_CONFIG}/config.json" <<'EOF'
{"credHelpers":{"ghcr.io":"desktop.exe"}}
EOF
	run env PATH="${FAKE_BIN}" DOTFILES_FORCE_WSL=1 RESULTS_FILE="$results_file" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" update --results "$results_file"
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"docker-credential-desktop.exe"* ]]
	[[ "${output}" == *"make install-docker-desktop-helper"* ]]
	assert_file_not_contains "${DOCKER_LOG}" 'pull ghcr.io/yctimlin/mcp_excalidraw'
	grep -q $'FAIL\tWSL\tExcalidraw Docker credentials\tDocker credential helper unavailable from PATH:' "$results_file"
	[[ "$(awk -F '\t' '$1=="FAIL" || $1=="WARN" || $1=="INCIDENT"{count++} END{print count + 0}' "$results_file")" -eq 1 ]]
}

@test "excalidraw update pulls when required helper is available" {
	cat >"${DOCKER_CONFIG}/config.json" <<'EOF'
{"credHelpers":{"ghcr.io":"desktop.exe"}}
EOF
	cat >"${FAKE_BIN}/docker-credential-desktop.exe" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "${FAKE_BIN}/docker-credential-desktop.exe"
	run env PATH="${FAKE_BIN}" DOTFILES_FORCE_WSL=1 bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" update
	[[ "${status}" -eq 0 ]]
	grep -q 'pull ghcr.io/yctimlin/mcp_excalidraw-canvas:latest' "${DOCKER_LOG}"
	grep -q 'pull ghcr.io/yctimlin/mcp_excalidraw:latest' "${DOCKER_LOG}"
}

@test "excalidraw start fails when dedicated port is occupied" {
	local occupied_bin="${TEST_TEMP_DIR}/occupied-bin"
	mkdir -p "$occupied_bin"
	cat >"${occupied_bin}/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$DOCKER_LOG"
case "$1" in
  info) exit 0 ;;
  ps|version|port) exit 0 ;;
  run) exit 0 ;;
  *) exit 0 ;;
esac
EOF
	chmod +x "${occupied_bin}/docker"
	python3 - <<'PY' &
import socket, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 3210))
s.listen(1)
time.sleep(6)
PY
	local listener_pid=$!
	sleep 1
	run env PATH="${occupied_bin}:/usr/bin:/bin" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" start
	kill "${listener_pid}" 2>/dev/null || true
	wait "${listener_pid}" 2>/dev/null || true
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"Port 3210 is already in use"* ]]
	run grep -q 'run -d' "${DOCKER_LOG}"
	[[ "${status}" -ne 0 ]]
}

@test "excalidraw start rejects stale canvas container with legacy port mapping" {
	local stale_bin="${TEST_TEMP_DIR}/stale-bin"
	mkdir -p "$stale_bin"
	cat >"${stale_bin}/docker" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$DOCKER_LOG"
case "$1" in
  info) exit 0 ;;
  version) exit 0 ;;
  ps)
    if [[ "$*" == *"--format"* ]]; then echo "mcp-excalidraw-canvas"; fi
    exit 0
    ;;
  port) echo "0.0.0.0:3000"; exit 0 ;;
  start|run) exit 0 ;;
  *) exit 0 ;;
esac
EOF
	chmod +x "${stale_bin}/docker"
	run env PATH="${stale_bin}:/usr/bin:/bin" EXCALIDRAW_SKIP_PORT_CHECK=1 bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" start
	[[ "${status}" -ne 0 ]]
	[[ "${output}" == *"unexpected port mapping"* ]]
	[[ "${output}" == *"Expected host port 3210"* ]]
	run grep -q 'run -d' "${DOCKER_LOG}"
	[[ "${status}" -ne 0 ]]
}

@test "excalidraw status warns on stale canvas container with legacy port mapping" {
	local stale_bin="${TEST_TEMP_DIR}/stale-status-bin"
	mkdir -p "$stale_bin"
	cat >"${stale_bin}/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  info) exit 0 ;;
  version) exit 0 ;;
  ps)
    if [[ "$*" == *"--format"* ]]; then echo "mcp-excalidraw-canvas"; fi
    exit 0
    ;;
  port) echo "0.0.0.0:3000"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
	chmod +x "${stale_bin}/docker"
	run env PATH="${stale_bin}:/usr/bin:/bin" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" status
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"unexpected port mapping"* ]]
	[[ "${output}" == *"3210:3000"* ]]
}

@test "MCP templates use ephemeral Docker, not local dist/index.js" {
	grep -q '"excalidraw_canvas"' "${DOTFILES_DIR}/dot_cursor/mcp.json.tmpl"
	grep -q '\[mcp_servers.excalidraw_canvas\]' "${DOTFILES_DIR}/dot_codex/private_config.toml.tmpl"
	grep -q '"excalidraw_canvas"' "${DOTFILES_DIR}/dot_config/opencode/opencode.json.tmpl"
	run grep -q '"excalidraw"' "${DOTFILES_DIR}/dot_cursor/mcp.json.tmpl"
	[[ "${status}" -ne 0 ]]
	run grep -q '\[mcp_servers.excalidraw\]' "${DOTFILES_DIR}/dot_codex/private_config.toml.tmpl"
	[[ "${status}" -ne 0 ]]
	grep -q 'ghcr.io/yctimlin/mcp_excalidraw:latest' "${DOTFILES_DIR}/dot_cursor/mcp.json.tmpl"
	grep -q 'ghcr.io/yctimlin/mcp_excalidraw:latest' "${DOTFILES_DIR}/dot_codex/private_config.toml.tmpl"
	grep -q 'ghcr.io/yctimlin/mcp_excalidraw:latest' "${DOTFILES_DIR}/dot_config/opencode/opencode.json.tmpl"
	grep -q 'EXPRESS_SERVER_URL=http://host.docker.internal:3210' "${DOTFILES_DIR}/dot_cursor/mcp.json.tmpl"
	grep -q 'EXPRESS_SERVER_URL=http://host.docker.internal:3210' "${DOTFILES_DIR}/dot_codex/private_config.toml.tmpl"
	grep -q 'EXPRESS_SERVER_URL=http://host.docker.internal:3210' "${DOTFILES_DIR}/dot_config/opencode/opencode.json.tmpl"
	grep -q 'EXCALIDRAW_EXPORT_DIR=/workspace/excalidraw' "${DOTFILES_DIR}/dot_cursor/mcp.json.tmpl"
	grep -q 'EXCALIDRAW_EXPORT_DIR=/workspace/excalidraw' "${DOTFILES_DIR}/dot_codex/private_config.toml.tmpl"
	grep -q 'EXCALIDRAW_EXPORT_DIR=/workspace/excalidraw' "${DOTFILES_DIR}/dot_config/opencode/opencode.json.tmpl"
	grep -q '{{ \$excalidrawWorkspaceHost }}:/workspace/excalidraw' "${DOTFILES_DIR}/dot_cursor/mcp.json.tmpl"
	grep -q '{{ \$excalidrawWorkspaceHost }}:/workspace/excalidraw' "${DOTFILES_DIR}/dot_codex/private_config.toml.tmpl"
	grep -q '{{ \$excalidrawWorkspaceHost }}:/workspace/excalidraw' "${DOTFILES_DIR}/dot_config/opencode/opencode.json.tmpl"
	grep -q 'excalidrawWorkspaceHost := default' "${DOTFILES_DIR}/dot_cursor/mcp.json.tmpl"
	run grep -R '/mnt/c/Users/jesus/Documents/vault_trabajo:/workspace/excalidraw' "${DOTFILES_DIR}/dot_cursor" "${DOTFILES_DIR}/dot_codex" "${DOTFILES_DIR}/dot_config/opencode"
	[[ "${status}" -ne 0 ]]
	run grep -R 'mcp-servers/excalidraw-mcp/dist/index.js' "${DOTFILES_DIR}/dot_cursor" "${DOTFILES_DIR}/dot_codex" "${DOTFILES_DIR}/dot_config/opencode"
	[[ "${status}" -ne 0 ]]
	run grep -R 'EXPRESS_SERVER_URL=http://host.docker.internal:3000' "${DOTFILES_DIR}/dot_cursor" "${DOTFILES_DIR}/dot_codex" "${DOTFILES_DIR}/dot_config/opencode"
	[[ "${status}" -ne 0 ]]
}

@test "excalidraw status tolerates missing Docker without fatal error" {
	local empty_path="${TEST_TEMP_DIR}/empty-path"
	mkdir -p "$empty_path"
	ln -s "$(command -v dirname)" "${empty_path}/dirname"
	local bash_abs
	bash_abs="$(command -v bash)"
	run env PATH="$empty_path" "$bash_abs" "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" status
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"No responsive Docker command found"* ]]
}

@test "excalidraw stop is tolerant when canvas is already stopped" {
	run env PATH="${FAKE_BIN}:/usr/bin:/bin" bash "${DOTFILES_DIR}/scripts/update/update-excalidraw.sh" stop
	[[ "${status}" -eq 0 ]]
	[[ "${output}" == *"already stopped"* ]]
}

@test "update-wsl MCP section updates Excalidraw images without starting canvas" {
	run env PATH="${FAKE_BIN}:/usr/bin:/bin" DOTFILES_UPDATE_RUN_DIR="${TEST_TEMP_DIR}/run-mcp" bash "${DOTFILES_DIR}/scripts/update/update-wsl.sh" --section mcp
	[[ "${status}" -eq 0 ]]
	grep -q 'pull ghcr.io/yctimlin/mcp_excalidraw-canvas:latest' "${DOCKER_LOG}"
	grep -q 'pull ghcr.io/yctimlin/mcp_excalidraw:latest' "${DOCKER_LOG}"
	assert_file_not_contains "${DOCKER_LOG}" 'run -d'
}

@test "Excalidraw manifest uses Docker image and no local checkout" {
	grep -q 'id: excalidraw_canvas' "${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml"
	run grep -q 'id: excalidraw$' "${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml"
	[[ "${status}" -ne 0 ]]
	grep -q 'ghcr.io/yctimlin/mcp_excalidraw:latest' "${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml"
	grep -q 'EXPRESS_SERVER_URL=http://host.docker.internal:3210' "${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml"
	grep -q 'EXCALIDRAW_EXPORT_DIR=/workspace/excalidraw' "${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml"
	grep -q 'excalidraw_workspace_host' "${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml"
	grep -q '3210:3000' "${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml"
	run grep -q 'mcp-servers/excalidraw-mcp/dist/index.js' "${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml"
	[[ "${status}" -ne 0 ]]
}

@test "Excalidraw active configuration does not use legacy host port 3000" {
	run grep -R 'EXPRESS_SERVER_URL=http://host.docker.internal:3000' \
		"${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml" \
		"${DOTFILES_DIR}/scripts/generate-mcp-configs.py" \
		"${DOTFILES_DIR}/dot_cursor" \
		"${DOTFILES_DIR}/dot_codex" \
		"${DOTFILES_DIR}/dot_config/opencode"
	[[ "${status}" -ne 0 ]]
	run grep -R '/mnt/c/Users/jesus/Documents/vault_trabajo:/workspace/excalidraw' \
		"${DOTFILES_DIR}/ai/assets/mcps/MANIFEST.yaml" \
		"${DOTFILES_DIR}/scripts/generate-mcp-configs.py" \
		"${DOTFILES_DIR}/dot_cursor" \
		"${DOTFILES_DIR}/dot_codex" \
		"${DOTFILES_DIR}/dot_config/opencode"
	[[ "${status}" -ne 0 ]]
}

@test "Excalidraw skills keep Docker, editable source, export, and safety rules" {
	local diagram_skill="${DOTFILES_DIR}/ai/assets/skills/diagrams/excalidraw/SKILL.md"
	local ops_skill="${DOTFILES_DIR}/ai/assets/skills/ops/excalidraw-mcp-operations/SKILL.md"
	local publish_skill="${DOTFILES_DIR}/ai/assets/skills/docs/excalidraw-publishing/SKILL.md"
	grep -q 'make excalidraw-start' "$ops_skill"
	grep -q 'excalidraw_canvas' "$ops_skill"
	grep -q 'Docker' "$ops_skill"
	grep -qi 'do not clone' "$ops_skill"
	grep -q 'excalidraw_canvas' "$diagram_skill"
	grep -q 'import_scene' "$diagram_skill"
	grep -q 'describe_scene' "$diagram_skill"
	grep -q 'update_element' "$diagram_skill"
	grep -q 'export_scene' "$diagram_skill"
	grep -q '/workspace/excalidraw' "$diagram_skill"
	grep -q '.excalidraw.md' "$diagram_skill"
	grep -q '.excalidraw' "$diagram_skill"
	grep -q 'import' "$diagram_skill"
	grep -Eq 'backup|snapshot|copy' "$diagram_skill"
	grep -q '/workspace/excalidraw' "$ops_skill"
	grep -q 'EXCALIDRAW_EXPORT_DIR=/workspace/excalidraw' "$ops_skill"
	grep -q 'SVG' "$publish_skill"
	grep -q '/workspace/excalidraw' "$publish_skill"
	grep -q '.excalidraw.md' "$publish_skill"
	grep -q '.excalidraw' "$publish_skill"
}
