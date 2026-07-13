#!/usr/bin/env bash
# Install agent-kit's authorship guards into .git/hooks (hooks are not versioned,
# so run this once per fresh clone). Idempotent.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
hooks="$root/.git/hooks"
mkdir -p "$hooks"

cat > "$hooks/commit-msg" <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/check-commit-msg.sh" < "$1"
EOF

cat > "$hooks/pre-push" <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/check-push-range.sh"
EOF

chmod +x "$hooks/commit-msg" "$hooks/pre-push"
echo "installed: commit-msg + pre-push authorship guards"
