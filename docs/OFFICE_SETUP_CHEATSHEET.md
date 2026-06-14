# Office setup cheatsheet

Quick recipe for validating and updating the office laptop without printing
secrets, touching HOME accidentally, or regenerating GitNexus surfaces.

This does not replace [INSTALL.md](INSTALL.md), [CHEZMOI.md](CHEZMOI.md),
[GUIA_MCP_AI.md](GUIA_MCP_AI.md), or [UPDATE.md](UPDATE.md). Use those when
you need the long-form explanation.

---

## 1. Purpose

Use this checklist on the office Windows/WSL machine to confirm the checkout,
Chezmoi data, secrets readiness, Docker Desktop bridge, MCP surfaces, and final
validation state. Keep read-only checks separate from commands that mutate HOME,
the system, Git history, or GitNexus indexes.

## 2. Assumptions

| Item | Expected |
|------|----------|
| Host | Windows 11 |
| Linux | WSL2 / Ubuntu |
| Repo | `~/dotfiles` |
| Fork remote | `origin` -> `IXATU/dotfiles` |
| Canonical upstream | `upstream` -> `jesuserro/dotfiles` |
| Branch | `dev` |

Local Obsidian and Excalidraw paths should come from Chezmoi data, not from
hardcoded repo paths. Keep office-specific paths in
`~/.config/chezmoi/chezmoi.toml`.

## 3. Safe initial status

```bash
cd ~/dotfiles
git status --short
git remote -v
git branch --show-current
```

Do not over-automate Git here. Jesus reviews branch, stage, push, merge, and
commit decisions manually.

## 4. Expected remotes

Expected shape:

```text
origin    IXATU/dotfiles
upstream  jesuserro/dotfiles
```

If `upstream` is missing:

```bash
git remote add upstream https://github.com/jesuserro/dotfiles.git
```

Human decision only: update local `dev` from canonical upstream:

```bash
git fetch --all --prune
git checkout dev
git pull --ff-only upstream dev
```

Push, merge conflict resolution, commits, and rebases are also human decisions.

## 5. Chezmoi checks

Read-only checks:

```bash
chezmoi --version
chezmoi doctor
chezmoi data
chezmoi --source="$HOME/dotfiles" status
chezmoi --source="$HOME/dotfiles" diff
```

Human decision only:

```bash
chezmoi apply
make install-dotfiles DOTFILES_APPLY=1
```

Do not run `chezmoi apply` automatically. If the diff is unclear, stop at
`status` / `diff` and inspect the affected paths first.

## 6. SOPS / Age / Secrets

Safe checks:

```bash
test -f ~/.config/sops/age/keys.txt && echo "OK: Age key exists"
age-keygen -y ~/.config/sops/age/keys.txt
sops --decrypt ./secrets.sops.yaml >/dev/null
make secrets-check
STRICT=1 make secrets-check
```

Rules:

- Do not paste `AGE-SECRET-KEY`.
- Do not paste tokens.
- Do not paste real DSNs.
- `age1...` is a public recipient.
- `AGE-SECRET-KEY...` is private.
- If `~/.config/sops/age/keys.txt` is lost, old secrets cannot be decrypted
  unless another valid recipient exists.

If `make secrets-check` shows a MinIO `444` warning, treat it as possible local
legacy debt first; it is not necessarily a blocker by itself.

## 7. Docker Desktop / WSL

Prefer Docker Desktop on Windows. Do not install Docker Engine inside WSL as the
first fix. The repo already has responsive fallback behavior for Excalidraw and
`update-check`.

Validate the normal Linux command first:

```bash
docker info
docker run hello-world
docker compose version
```

If `docker` fails but `docker.exe` works:

```bash
docker.exe info
docker.exe run hello-world
docker.exe compose version
```

Optional local wrapper, outside the repo:

```text
~/.local/bin/docker
```

```bash
#!/usr/bin/env bash
exec docker.exe "$@"
```

```bash
chmod +x ~/.local/bin/docker
```

## 8. Cursor / Codex / OpenCode / Excalidraw

Main readiness check:

```bash
make ai-cursor-check
```

Excalidraw workspace resolution order:

```text
EXCALIDRAW_WORKSPACE_HOST
Chezmoi data.ai.excalidraw_workspace_host
Chezmoi data.ai.obsidian_vault_path/excalidraw
fallback legacy final
```

Do not treat legacy paths as canonical. Expected result is
`Cursor readiness: PASS`, or at least no warnings about a missing legacy
Excalidraw path.

## 9. GitNexus

Allowed for a human, with care:

```bash
make gitnexus-status
gnx-analyze-here --skip-agents-md
```

Avoid:

```bash
gnx-analyze-here
```

without `--skip-agents-md`, because it may regenerate `AGENTS.md` and
`CLAUDE.md` GitNexus blocks. Do not edit these blocks without explicit review:

```text
<!-- gitnexus:* -->
```

Agents must not run GitNexus analyze, wiki, clean, or refresh commands unless
Jesus explicitly asks for that mutation.

## 10. Final validation sequence

Recommended close-out:

```bash
cd ~/dotfiles
make secrets-check
STRICT=1 make secrets-check
make ai-cursor-check
make update-check
make install-verify
make agent-validate-changed
```

Expected:

- SOPS decrypt works.
- Docker responds.
- `make ai-cursor-check` has no missing legacy Excalidraw path.
- `make update-check` has no false Docker warning when `docker.exe` responds.
- `make install-verify` passes.
- `make agent-validate-changed` passes.

## 11. Troubleshooting

| Symptom | Likely cause | Safe action |
|---------|--------------|-------------|
| Age key missing | `~/.config/sops/age/keys.txt` was not restored | Restore the correct private key manually; do not generate a new key expecting old secrets to decrypt |
| `sops decrypt failed` | Wrong or missing Age private key, or recipient mismatch | Check `age-keygen -y ~/.config/sops/age/keys.txt` and `.sops.yaml` recipient |
| `docker info` fails but `docker.exe info` works | WSL `docker` wrapper/CLI path is wrong | Use `docker.exe` directly or add the optional local wrapper |
| `make ai-cursor-check` shows MISSING Excalidraw | Chezmoi data for vault/workspace is missing or points to an unavailable path | Set local Chezmoi data and re-run readiness checks before applying |
| `make secrets-check` shows MinIO `444` | Local legacy MinIO compatibility state | Treat as warning first unless the current workflow depends on MinIO |
| `chezmoi apply` fails | RC backup guard, missing SOPS/Age, or template/runtime issue | Read the error, inspect `chezmoi status/diff`, and prefer acotado apply |
| GitNexus tries to touch `AGENTS.md` / `CLAUDE.md` | Analyze ran without `--skip-agents-md` | Stop and review diff manually; use `gnx-analyze-here --skip-agents-md` next time |

## Related docs

- [INSTALL.md](INSTALL.md)
- [CHEZMOI.md](CHEZMOI.md)
- [SECRETS_EXAMPLES.md](SECRETS_EXAMPLES.md)
- [GUIA_MCP_AI.md](GUIA_MCP_AI.md)
- [UPDATE.md](UPDATE.md)
- [GITNEXUS_OPERATIONAL_POLICY.md](GITNEXUS_OPERATIONAL_POLICY.md)
- [OPERATIONS_CHEATSHEET.md](OPERATIONS_CHEATSHEET.md)
