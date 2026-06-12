#!/usr/bin/env bash
# pubifact — turn a local .html or .md file into a shareable URL.
#
# Tiers (first that works wins, so it works for everyone with zero setup):
#   1. Hosted endpoint — $PUBIFACT_ENDPOINT (our Worker). No account, persistent.
#   2. tmpfiles.org    — no account, emergency fallback, link expires in ~1 hour.
#
# Usage:
#   publish.sh <file>                      # .html or .md
#   publish.sh <file> --password <secret>  # require the secret to VIEW the page
#
# With --password (or $PUBIFACT_PASSWORD) the page is read-protected: viewers
# get an HTTP Basic prompt (any username + the secret) or append ?k=<secret>.
# A password forces the hosted endpoint only — it never falls back to an
# unprotected public host.
set -euo pipefail

# Defaults to the reference instance so it works with no setup.
# Self-hosting? Override: export PUBIFACT_ENDPOINT=https://pubifact.<you>.workers.dev
ENDPOINT="${PUBIFACT_ENDPOINT:-https://pubifact.domuk-k.workers.dev}"

file=''
password="${PUBIFACT_PASSWORD:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p | --password)
      password="${2:-}"
      shift 2
      ;;
    -h | --help)
      echo "usage: publish.sh <file> [--password <secret>]" >&2
      exit 0
      ;;
    *)
      [ -z "$file" ] && file="$1"
      shift
      ;;
  esac
done

{ [ -n "$file" ] && [ -f "$file" ]; } || {
  echo "usage: publish.sh <file> [--password <secret>]" >&2
  exit 2
}

log() { printf '%s\n' "$*" >&2; }

# --- tier 1: hosted endpoint (zero setup) ---
if [ -n "$ENDPOINT" ]; then
  args=(-F "file=@${file}")
  [ -n "$password" ] && args+=(-F "password=${password}")
  if url=$(curl -fsS "${args[@]}" "${ENDPOINT%/}/up" 2>/dev/null) && [ -n "$url" ]; then
    printf '%s\n' "$url"
    [ -n "$password" ] && log "(read-protected — share the password separately)"
    exit 0
  fi
  log "hosted endpoint unavailable…"
fi

# A password must never leak to an unprotected host — stop here.
if [ -n "$password" ]; then
  log "refusing to fall back to an unprotected host for a password-protected file"
  exit 1
fi

# --- tier 2: tmpfiles.org (no account, ~1h expiry) — emergency fallback only ---
if resp=$(curl -fsS -F "file=@${file}" https://tmpfiles.org/api/v1/upload 2>/dev/null); then
  raw="$(printf '%s' "$resp" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
  if [ -n "$raw" ]; then
    # /dl/ path serves the file directly.
    printf '%s\n' "${raw/tmpfiles.org\//tmpfiles.org/dl/}"
    log "(temporary link — expires in ~1 hour)"
    exit 0
  fi
fi

log "all publish methods failed — check connectivity or set PUBIFACT_ENDPOINT"
exit 1
