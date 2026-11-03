#!/bin/sh
# Reads the admin panel's data as an agent: GET https://$BILLET_ADMIN_HOST/admin/api/agent/<route>
# with the agents' Cloudflare Access service token, and prints the JSON answer. Read-only: the
# Worker refuses every write from a service token. See docs/admin.md#agent-api.
#
#   PROTON_PASS_AGENT_REASON="<why>" pp run --env-file .env.pass.agents -- scripts/admin-read.sh flags
#
# Routes: overview, experiments, flags, flag-history[?key=<key>&limit=<1-500>], pairs/<pair id>,
# status, status-history[?limit=<1-200>].
# Needs CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET in the environment (`.env.pass.agents`
# resolves them); the credentials go to curl on stdin, never on its command line. The API host is
# BILLET_ADMIN_HOST, from the environment or else from a local file that is never committed:
# $BILLET_ADMIN_ENV_FILE, by default ~/.config/billet/admin.env, with a line BILLET_ADMIN_HOST=<host>.
set -eu

usage() {
  echo "usage: admin-read.sh overview|experiments|flags|flag-history[?query]|status|status-history[?query]|pairs/<pair id>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
route=$1
case "$route" in
  overview | experiments | flags | status) ;;
  status-history | status-history\?*)
    printf '%s' "$route" | grep -Eq '^status-history(\?limit=[0-9]{1,3})?$' || usage
    ;;
  flag-history | flag-history\?*)
    printf '%s' "$route" | grep -Eq '^flag-history(\?[A-Za-z0-9_=&.-]*)?$' || usage
    ;;
  pairs/*)
    printf '%s' "$route" | grep -Eq '^pairs/[A-Za-z0-9_-]{1,128}$' || usage
    ;;
  *) usage ;;
esac

if [ -z "${BILLET_ADMIN_HOST:-}" ]; then
  env_file=${BILLET_ADMIN_ENV_FILE:-$HOME/.config/billet/admin.env}
  if [ -f "$env_file" ]; then
    BILLET_ADMIN_HOST=$(sed -n 's/^BILLET_ADMIN_HOST=//p' "$env_file" | tail -n 1 | tr -d "\"' ")
  fi
fi

for name in BILLET_ADMIN_HOST CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET; do
  eval "value=\${$name:-}"
  case "$value" in
    "" | pass://*)
      echo "admin-read.sh: $name is not set (see the top of this script)" >&2
      exit 2
      ;;
  esac
done
printf '%s' "$BILLET_ADMIN_HOST" | grep -Eq '^[A-Za-z0-9.-]+$' || {
  echo "admin-read.sh: BILLET_ADMIN_HOST must be a bare host name" >&2
  exit 2
}

body=$(mktemp)
trap 'rm -f "$body"' EXIT
status=$(
  printf 'header = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' \
    "$CF_ACCESS_CLIENT_ID" "$CF_ACCESS_CLIENT_SECRET" |
    curl --silent --show-error --proto '=https' --max-time 30 --config - \
      --output "$body" --write-out '%{http_code}' \
      "https://$BILLET_ADMIN_HOST/admin/api/agent/$route"
)
if [ "$status" = "200" ]; then
  cat "$body"
  echo
  exit 0
fi
case "$status" in
  302 | 401 | 403) echo "admin-read.sh: HTTP $status: the service token was not accepted" >&2 ;;
  *) echo "admin-read.sh: HTTP $status" >&2 ;;
esac
exit 1
