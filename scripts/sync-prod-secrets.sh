#!/usr/bin/env bash
# Copies the prod secrets from Proton Pass into the GitHub environment `prod`, for the deploy
# workflow. Run by the owner on the Mac where `pp` and `gh` are logged in. Values go through a pipe
# into `gh secret set` and are never printed or passed as arguments.
#
#   scripts/sync-prod-secrets.sh            copy every variable in .env.pass.release
#   scripts/sync-prod-secrets.sh --dry-run  list the names only
#
# .env.pass.release is the single list; to rotate, change the value in Proton Pass and run this again.
# The pp session must be able to read the prod vault (the owner's own login, not the agents' session;
# docs/alchemy.md#deploy-workflow).
set -euo pipefail

repo=mikitahimpel/billet
env_name=prod
root=$(cd "$(dirname "$0")/.." && pwd)
env_file="$root/.env.pass.release"
dry_run=0

case "${1:-}" in
  "") ;;
  --dry-run) dry_run=1 ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

names=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" | cut -d= -f1)

if [ "$dry_run" = 1 ]; then
  echo "Would copy into the GitHub environment '$env_name' of $repo:"
  printf '  %s\n' $names
  exit 0
fi

command -v pp >/dev/null || { echo "pp (Proton Pass CLI) is not installed" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh is not installed" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not logged in: run gh auth login" >&2; exit 1; }

export PROTON_PASS_AGENT_REASON="${PROTON_PASS_AGENT_REASON:-sync prod secrets to GitHub environment prod}"

# These may not exist in Proton Pass yet (the first deploy runs without them); a missing one is skipped.
optional=" ACCESS_TEAM_DOMAIN ACCESS_AUD TMDB_TOKEN API_DOMAIN "
skipped=""
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for name in $names; do
  # One reference per run, so an item that does not exist yet fails only its own variable.
  grep -E "^$name=" "$env_file" > "$tmp/one.env"
  # The variable name is the only text in the command string; the value stays in the environment.
  if pp run --env-file "$tmp/one.env" -- sh -c \
    "test -n \"\$$name\" || exit 1
     printf %s \"\$$name\" | gh secret set $name --env $env_name --repo $repo" 2>/dev/null; then
    echo "set $name"
  elif [ "${optional#* $name }" != "$optional" ]; then
    skipped="$skipped $name"
  else
    echo "failed: $name is required and did not resolve or could not be set" >&2
    exit 1
  fi
done

if [ -n "$skipped" ]; then echo "Skipped (item not in Proton Pass yet):$skipped"; fi
echo
echo "Secrets in the environment '$env_name' (names only):"
gh secret list --env "$env_name" --repo "$repo"
