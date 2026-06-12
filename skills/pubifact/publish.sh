#!/usr/bin/env bash
# pubifact — turn a local .html or .md file into a shareable URL.
#
# Publishing needs a configured instance: an `endpoint` in
# ~/.config/pubifact/config.json (written by init.sh) or $PUBIFACT_ENDPOINT.
# With none configured, this script points you at init.sh to set up your own
# free permanent instance in ~2 minutes. It deliberately does NOT fall back to
# an anonymous public host — those reject HTML/Markdown unpredictably and leak
# your content to a host you don't control.
#
# Usage:
#   publish.sh <file>                      # .html or .md
#   publish.sh <file> --password <secret>  # require the secret to VIEW the page
#   publish.sh --down <url> --token <tok>  # take a published page back down
#
# With --password (or $PUBIFACT_PASSWORD) the page is read-protected: viewers
# get an HTTP Basic prompt (any username + the secret) or append ?k=<secret>.
#
# On publish, a one-time delete token is printed to the logs (stderr). Keep it
# to take the page down later with --down (or set $PUBIFACT_DELETE_TOKEN).
#
# Exit codes:
#   0  success
#   1  could not reach / publish to the configured instance
#   2  usage error (bad arguments / file not found)
#   3  no instance configured yet — run init.sh
#   4  instance auth or size error (401/403/413 — check config)
set -euo pipefail

# --- config (env var > config file > nothing) ---
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/pubifact/config.json"
json_get() { sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n1; }

ENDPOINT="${PUBIFACT_ENDPOINT:-}"
TOKEN="${PUBIFACT_TOKEN:-}"
if [ -z "$ENDPOINT" ] && [ -f "$CONFIG" ]; then
  ENDPOINT="$(json_get "$CONFIG" endpoint)"
fi
if [ -z "$TOKEN" ] && [ -f "$CONFIG" ]; then
  TOKEN="$(json_get "$CONFIG" token)"
fi

# --- arg parsing ---
file=''
password="${PUBIFACT_PASSWORD:-}"
down_url=''
delete_token="${PUBIFACT_DELETE_TOKEN:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p | --password)
      password="${2:-}"
      shift 2
      ;;
    --down)
      down_url="${2:-}"
      shift 2
      ;;
    --token)
      delete_token="${2:-}"
      shift 2
      ;;
    -h | --help)
      printf 'usage: publish.sh <file> [--password <secret>]\n       publish.sh --down <url> --token <delete-token>\n' >&2
      exit 0
      ;;
    *)
      [ -z "$file" ] && file="$1"
      shift
      ;;
  esac
done

log() { printf '%s\n' "$*" >&2; }

# Resolve the skill directory from the script's own real path (init.sh hints).
# shellcheck disable=SC2155  # combined declare+assign: safe here, only used for messages
SKILL_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"

# --- takedown mode: DELETE a published page ---
if [ -n "$down_url" ]; then
  if [ -z "$delete_token" ]; then
    log "pubifact: a delete token is required to take a page down — pass --token <tok> or set \$PUBIFACT_DELETE_TOKEN"
    exit 2
  fi
  # `|| true`: keep -e from killing us before we can read the status trailer.
  down_status="$(curl -sS -o /dev/null -w '%{http_code}' \
    -X DELETE -H "Authorization: Bearer ${delete_token}" "$down_url" || true)"
  case "$down_status" in
    200)
      log "pubifact: taken down — $down_url is gone"
      printf 'taken down\n'
      exit 0
      ;;
    401)
      log "pubifact: wrong or missing delete token (HTTP 401) — cannot take down $down_url"
      exit 4
      ;;
    404)
      log "pubifact: already gone or unknown URL (HTTP 404) — $down_url"
      exit 1
      ;;
    000)
      log "pubifact: could not reach the host to take down $down_url (curl error)"
      exit 1
      ;;
    *)
      log "pubifact: takedown failed (HTTP $down_status) for $down_url"
      exit 1
      ;;
  esac
fi

{ [ -n "$file" ] && [ -f "$file" ]; } || {
  printf 'usage: publish.sh <file> [--password <secret>]\n' >&2
  exit 2
}

# --- no instance configured → point at one-time setup (init-first) ---
if [ -z "$ENDPOINT" ]; then
  log "pubifact: no instance configured yet — nothing was uploaded."
  log "pubifact: set up your own free permanent instance (~2 min): ${SKILL_DIR}/init.sh"
  exit 3
fi

# --- publish to the configured instance ---
curl_args=(-sS -w '\n%{http_code}' -F "file=@${file}")
[ -n "$password" ] && curl_args+=(-F "password=${password}")
[ -n "$TOKEN" ] && curl_args+=(-H "Authorization: Bearer ${TOKEN}")

# `|| true`: on connection failure curl still emits the -w "000" trailer but
# exits non-zero, which would kill the script under set -e.
raw_response="$(curl "${curl_args[@]}" "${ENDPOINT%/}/up" || true)"
http_status="${raw_response##*$'\n'}"
body="${raw_response%$'\n'*}"

case "$http_status" in
  200)
    # Response body is up to two lines: line 1 = URL, line 2 = delete token.
    # stdout MUST stay URL-only (the capture contract); the token goes to stderr.
    url="${body%%$'\n'*}"
    pub_token=''
    [ "$body" != "$url" ] && pub_token="${body#*$'\n'}"
    pub_token="${pub_token%%$'\n'*}" # first line only — body may carry a trailing newline
    if [ -n "$url" ]; then
      printf '%s\n' "$url"
      [ -n "$password" ] && log "(read-protected — share the password separately)"
      if [ -n "$pub_token" ]; then
        log "pubifact: take it down later with: publish.sh --down ${url} --token ${pub_token}"
      fi
      exit 0
    fi
    log "pubifact: instance returned 200 but an empty body — nothing to share"
    exit 1
    ;;
  401 | 403)
    log "pubifact: authentication error (HTTP $http_status) — check your token in $CONFIG"
    exit 4
    ;;
  413)
    log "pubifact: file too large (HTTP 413) — your instance rejected this upload"
    exit 4
    ;;
  000)
    log "pubifact: could not reach your instance at ${ENDPOINT} — is it deployed? (re-run ${SKILL_DIR}/init.sh to verify)"
    exit 1
    ;;
  *)
    log "pubifact: your instance returned HTTP $http_status"
    exit 1
    ;;
esac
