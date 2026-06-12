#!/usr/bin/env bash
# pubifact-init — one-time bootstrap: provision your own free artifact server.
#
# Wraps the hosting provider's CLI (wrangler) so an agent can drive setup
# without the user ever touching it. This script emits a structured protocol
# only — all human-facing narration lives in SKILL.md.
#
# Subcommands:
#   init.sh check                read-only: prereqs, login state, existing config
#   init.sh login                browser OAuth login (relays the URL for the user)
#   init.sh setup [flags]        bucket → deploy → token → config → verify
#   init.sh [flags]              no subcommand: check, then setup if logged in
#
# Setup flags:
#   --subdomain NAME    register NAME.workers.dev if the account has none yet
#   --no-token          skip the upload token (anyone can publish to the instance)
#   --force             overwrite a config that points at a different endpoint
#   --worker-src DIR    use DIR as the worker source instead of auto-detection
#
# Output protocol (agent-facing):
#   stderr   pubifact-init: [n/6] <step>              progress
#   stdout   ACTION_REQUIRED <kind>: <payload>        blocked on the user
#            kinds: login-url, enable-r2, subdomain, subdomain-manual, choose-account
#   stdout   RESULT endpoint=<url> token=<hex|none>   success
#
# Exit codes:
#   0   done (or already set up)
#   10  needs login — run init.sh login
#   11  needs a workers.dev subdomain
#   12  R2 not enabled on the account
#   13  deploy or prerequisite failure
#   14  deployed and configured, but verification failed (likely DNS lag — config kept)
set -euo pipefail

REPO="domuk-k/pubifact"
BUCKET_NAME="pubifact"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/pubifact/config.json"
# PUBIFACT_INIT_RETRY_DELAY is a test-only override so suites don't sleep 60s.
RETRY_DELAY="${PUBIFACT_INIT_RETRY_DELAY:-10}"
RETRY_COUNT=6

# Same flat-config reader as publish.sh — config.json is our own format
# (one key per line, string values only), no jq needed.
json_get() { sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n1; }

log() { printf '%s\n' "$*" >&2; }
step() { printf 'pubifact-init: [%s/6] %s\n' "$1" "$2" >&2; }
action() { printf 'ACTION_REQUIRED %s: %s\n' "$1" "$2"; }

usage() {
  log "usage: init.sh [check|login|setup] [--subdomain NAME] [--no-token] [--force] [--worker-src DIR]"
}

# Resolve the skill directory from the script's own real path (symlink-safe,
# same fallback chain as publish.sh — macOS readlink may lack -f).
script_path="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$script_path")" && pwd)"

TMP_SRC_DIR=''
cleanup() {
  if [ -n "$TMP_SRC_DIR" ]; then rm -rf "$TMP_SRC_DIR"; fi
}
trap cleanup EXIT

# --- globals filled in as setup progresses ---
worker_src=''
deploy_out=''
endpoint=''
token=''
check_state='' # 'configured' when an existing config answers

require_prereqs() {
  command -v node >/dev/null 2>&1 || {
    log "pubifact-init: node is required but not found — install Node.js >= 18 first"
    exit 13
  }
  command -v npx >/dev/null 2>&1 || {
    log "pubifact-init: npx is required but not found — install Node.js >= 18 first"
    exit 13
  }
}

# Run wrangler with cwd = the worker source dir (deploy/secret read wrangler.jsonc).
wr() { (cd "$worker_src" && npx -y wrangler@4 "$@"); }

# --- worker source acquisition: --worker-src flag → repo checkout → GitHub tarball ---
resolve_worker_src() {
  if [ -n "$worker_src_flag" ]; then
    if [ ! -f "$worker_src_flag/wrangler.jsonc" ]; then
      log "pubifact-init: --worker-src ${worker_src_flag} has no wrangler.jsonc — not a worker source dir"
      exit 13
    fi
    worker_src="$worker_src_flag"
    return 0
  fi

  local candidate="$SCRIPT_DIR/../../worker"
  if [ -f "$candidate/wrangler.jsonc" ]; then
    worker_src="$(cd "$candidate" && pwd)"
    return 0
  fi

  log "pubifact-init: fetching worker source from github.com/${REPO}"
  TMP_SRC_DIR="$(mktemp -d)"
  if ! curl -fsSL "https://github.com/${REPO}/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP_SRC_DIR"; then
    log "pubifact-init: could not download the worker source — check connectivity and retry"
    exit 13
  fi
  worker_src="$TMP_SRC_DIR/pubifact-main/worker"
  if [ ! -f "$worker_src/wrangler.jsonc" ]; then
    log "pubifact-init: downloaded source has no worker/wrangler.jsonc — report this at github.com/${REPO}/issues"
    exit 13
  fi
}

# --- [2/6] R2 bucket (idempotent) ---
do_bucket() {
  local out rc=0
  out="$(wr r2 bucket create "$BUCKET_NAME" 2>&1)" || rc=$?
  printf '%s\n' "$out" >&2
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  if printf '%s' "$out" | grep -qi 'already exists'; then
    log "pubifact-init: bucket '${BUCKET_NAME}' already exists — reusing it"
    return 0
  fi
  if printf '%s' "$out" | grep -qiE '10042|enable r2|not entitled'; then
    log "pubifact-init: R2 storage must be enabled once on this account (free tier is fine)"
    action enable-r2 "https://dash.cloudflare.com/?to=/:account/r2"
    exit 12
  fi
  log "pubifact-init: could not create the storage bucket — see output above"
  exit 13
}

# --- [3/6] deploy (non-interactive first; stdin-feed retry for fresh subdomains) ---
do_deploy() {
  local out rc=0
  # stdin closed so wrangler can never hang on a prompt.
  out="$(wr deploy </dev/null 2>&1)" || rc=$?
  printf '%s\n' "$out" >&2

  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'workers\.dev subdomain'; then
    if [ -z "$subdomain" ]; then
      log "pubifact-init: this account has no workers.dev subdomain yet — pick one and re-run"
      action subdomain "re-run setup with --subdomain <name> (lowercase letters, digits and hyphens)"
      exit 11
    fi
    log "pubifact-init: retrying deploy and registering subdomain '${subdomain}'"
    rc=0
    out="$(printf 'yes\n%s\nyes\n' "$subdomain" | wr deploy 2>&1)" || rc=$?
    printf '%s\n' "$out" >&2
    if [ "$rc" -ne 0 ]; then
      log "pubifact-init: automatic subdomain registration failed — register one in the dashboard, then re-run setup"
      action subdomain-manual "https://dash.cloudflare.com/?to=/:account/workers/onboarding"
      exit 11
    fi
  elif [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'more than one account'; then
    local accounts
    # Wrangler lists accounts as `Name`: `id` — backticks are literal output.
    # shellcheck disable=SC2016
    accounts="$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*`\(..*\)`: `\(..*\)`.*$/\1=\2/p' | paste -sd, - || true)"
    log "pubifact-init: multiple accounts found — set CLOUDFLARE_ACCOUNT_ID to the chosen account id and re-run setup"
    action choose-account "${accounts:-set CLOUDFLARE_ACCOUNT_ID and re-run setup}"
    exit 13
  elif [ "$rc" -ne 0 ]; then
    log "pubifact-init: deploy failed — see output above"
    exit 13
  fi

  deploy_out="$out"
  endpoint="$(printf '%s\n' "$deploy_out" | grep -oE 'https://[a-z0-9.-]+\.workers\.dev' | head -n1 || true)"
  if [ -z "$endpoint" ]; then
    log "pubifact-init: deploy succeeded but no workers.dev URL appeared in the output — see above"
    exit 13
  fi
}

# --- [4/6] upload token (default on; --no-token opts out) ---
do_token() {
  local out rc=0
  token="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n' || true)"
  if [ -z "$token" ]; then
    log "pubifact-init: could not generate a random token"
    exit 13
  fi
  out="$(printf '%s' "$token" | wr secret put UPLOAD_TOKEN 2>&1)" || rc=$?
  printf '%s\n' "$out" >&2
  if [ "$rc" -ne 0 ]; then
    log "pubifact-init: could not set the upload token — see output above"
    exit 13
  fi
}

# --- [5/6] config write (atomic, 600 perms, refuses to clobber a different endpoint) ---
do_config() {
  if [ -f "$CONFIG" ]; then
    local existing
    existing="$(json_get "$CONFIG" endpoint)"
    if [ -n "$existing" ] && [ "$existing" != "$endpoint" ] && [ "$force" != true ]; then
      log "pubifact-init: ${CONFIG} already points at ${existing} — re-run with --force to overwrite"
      exit 13
    fi
  fi
  (
    umask 077
    mkdir -p "$(dirname "$CONFIG")"
    if [ -n "$token" ]; then
      printf '{\n  "endpoint": "%s",\n  "token": "%s"\n}\n' "$endpoint" "$token" >"$CONFIG.tmp"
    else
      printf '{\n  "endpoint": "%s"\n}\n' "$endpoint" >"$CONFIG.tmp"
    fi
    mv "$CONFIG.tmp" "$CONFIG"
  )
  log "pubifact-init: config written to ${CONFIG}"
}

# --- [6/6] verify: publish a tiny test page (fresh workers.dev DNS can lag) ---
do_verify() {
  local page raw status i
  page="$(mktemp)"
  printf '<!doctype html><title>pubifact verify</title><p>ok</p>\n' >"$page"
  local args=(-sS -w '\n%{http_code}' --max-time 15 -F "file=@${page}")
  if [ -n "$token" ]; then
    args+=(-H "Authorization: Bearer ${token}")
  fi
  for ((i = 1; i <= RETRY_COUNT; i++)); do
    raw="$(curl "${args[@]}" "${endpoint%/}/up" 2>/dev/null || true)"
    status="${raw##*$'\n'}"
    if [ "$status" = "200" ]; then
      rm -f "$page"
      return 0
    fi
    if [ "$status" = "401" ] || [ "$status" = "403" ]; then
      rm -f "$page"
      log "pubifact-init: the instance is up but rejected the upload token (HTTP ${status})"
      log "pubifact-init: config is saved — re-run setup to rotate the token if this persists"
      exit 14
    fi
    if [ "$i" -lt "$RETRY_COUNT" ]; then
      log "pubifact-init: not answering yet (HTTP ${status:-?}) — retrying in ${RETRY_DELAY}s (${i}/${RETRY_COUNT})"
      sleep "$RETRY_DELAY"
    fi
  done
  rm -f "$page"
  log "pubifact-init: deployed and configured, but the endpoint didn't answer yet."
  log "pubifact-init: fresh workers.dev DNS can take a few minutes — nothing is broken and your config is saved. Try publishing again shortly."
  exit 14
}

# --- subcommands ---

cmd_check() {
  require_prereqs

  local cfg_endpoint=''
  if [ -f "$CONFIG" ]; then
    cfg_endpoint="$(json_get "$CONFIG" endpoint)"
  fi
  if [ -n "$cfg_endpoint" ]; then
    local raw status
    raw="$(curl -sS -w '\n%{http_code}' --max-time 8 "${cfg_endpoint%/}/" 2>/dev/null || true)"
    status="${raw##*$'\n'}"
    if [ "$status" = "200" ]; then
      log "pubifact-init: already set up — ${cfg_endpoint} is configured and answering"
      check_state='configured'
      return 0
    fi
    log "pubifact-init: config points at ${cfg_endpoint} but it isn't answering (HTTP ${status:-?}) — setup can redeploy it"
  fi

  local who_out who_rc=0
  who_out="$(npx -y wrangler@4 whoami 2>&1)" || who_rc=$?
  printf '%s\n' "$who_out" >&2
  if [ "$who_rc" -ne 0 ] || printf '%s' "$who_out" | grep -qi 'not authenticated'; then
    log "pubifact-init: not logged in to the hosting account — run: init.sh login"
    exit 10
  fi
  log "pubifact-init: logged in and ready — run: init.sh setup"
  return 0
}

# Stream wrangler login output to stderr while re-emitting the OAuth URL as a
# structured line on stdout (the agent relays it to the user).
relay_login() {
  local line url emitted=false
  while IFS= read -r line; do
    printf '%s\n' "$line" >&2
    if [ "$emitted" = false ]; then
      url="$(printf '%s\n' "$line" | grep -oE 'https://[^[:space:]]*oauth[^[:space:]]*' || true)"
      if [ -n "$url" ]; then
        action login-url "$url"
        emitted=true
      fi
    fi
  done
}

cmd_login() {
  require_prereqs
  local rc=0
  npx -y wrangler@4 login 2>&1 | relay_login || rc=$?
  exit "$rc"
}

cmd_setup() {
  require_prereqs

  step 1 "locating worker source"
  resolve_worker_src
  log "pubifact-init: using worker source at ${worker_src}"

  step 2 "creating storage bucket"
  do_bucket

  step 3 "deploying your artifact server"
  do_deploy

  if [ "$want_token" = true ]; then
    step 4 "setting upload token"
    do_token
  else
    step 4 "skipping upload token (--no-token)"
    token=''
  fi

  step 5 "writing config"
  do_config

  step 6 "verifying the instance"
  do_verify

  printf 'RESULT endpoint=%s token=%s\n' "$endpoint" "${token:-none}"
  exit 0
}

# --- argument parsing + dispatch ---

subcmd=''
case "${1:-}" in
  check | login | setup)
    subcmd="$1"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
esac

subdomain=''
force=false
want_token=true
worker_src_flag=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --subdomain)
      if [ "$#" -lt 2 ]; then
        log "pubifact-init: --subdomain needs a value"
        exit 13
      fi
      subdomain="$2"
      shift 2
      ;;
    --no-token)
      want_token=false
      shift
      ;;
    --force)
      force=true
      shift
      ;;
    --worker-src)
      if [ "$#" -lt 2 ]; then
        log "pubifact-init: --worker-src needs a value"
        exit 13
      fi
      worker_src_flag="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      log "pubifact-init: unknown argument: $1"
      usage
      exit 13
      ;;
  esac
done

case "$subcmd" in
  check)
    cmd_check
    exit 0
    ;;
  login)
    cmd_login
    ;;
  setup)
    cmd_setup
    ;;
  '')
    cmd_check
    if [ "$check_state" = 'configured' ]; then
      exit 0
    fi
    cmd_setup
    ;;
esac
