#!/usr/bin/env bats
# Tests for skills/pubifact/init.sh
#
# Requires: bats-core >= 1.5.0, stub npx + curl at tests/stubs/
bats_require_minimum_version 1.5.0

INIT_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/pubifact/init.sh"

# Same extractor publish.sh uses — config written by init.sh must satisfy it.
json_get() { sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n1; }

setup() {
  # Prepend the stub directory so stub npx/curl take priority.
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Isolate config from the real user config.
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  CFG="$XDG_CONFIG_HOME/pubifact/config.json"

  # Clear env vars that might bleed in from the real environment.
  unset PUBIFACT_ENDPOINT PUBIFACT_TOKEN PUBIFACT_PASSWORD
  unset CLOUDFLARE_ACCOUNT_ID

  # Stub behavior defaults: everything succeeds.
  export WHOAMI_MODE=ok LOGIN_MODE=ok BUCKET_MODE=ok DEPLOY_MODE=ok SECRET_MODE=ok
  export CURL_MODE=ok

  # Invocation logs + per-test deploy call counter.
  export NPX_LOG="$BATS_TEST_TMPDIR/npx.log"
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  export NPX_STATE_DIR="$BATS_TEST_TMPDIR"

  # Don't actually sleep between verify retries.
  export PUBIFACT_INIT_RETRY_DELAY=0
}

write_config() {
  # write_config <endpoint> [token]
  mkdir -p "$XDG_CONFIG_HOME/pubifact"
  if [ "$#" -ge 2 ]; then
    printf '{\n  "endpoint": "%s",\n  "token": "%s"\n}\n' "$1" "$2" >"$CFG"
  else
    printf '{\n  "endpoint": "%s"\n}\n' "$1" >"$CFG"
  fi
}

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

@test "check: logged in, no config → exit 0" {
  run bash "$INIT_SH" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"logged in"* ]]
}

@test "check: not logged in → exit 10" {
  export WHOAMI_MODE=not-logged-in
  run bash "$INIT_SH" check
  [ "$status" -eq 10 ]
  [[ "$output" == *"not logged in"* ]]
}

@test "check: existing reachable config → already set up, exit 0" {
  write_config "https://pubifact.test-account.workers.dev" "tok123"
  run bash "$INIT_SH" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"already set up"* ]]
}

@test "check: existing config unreachable → still exit 0 when logged in" {
  write_config "https://pubifact.test-account.workers.dev"
  export CURL_MODE=all-down
  run bash "$INIT_SH" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't answering"* ]]
}

# ---------------------------------------------------------------------------
# login
# ---------------------------------------------------------------------------

@test "login: re-emits the OAuth URL as ACTION_REQUIRED login-url on stdout" {
  run --separate-stderr bash "$INIT_SH" login
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACTION_REQUIRED login-url: https://dash.cloudflare.com/oauth2/auth"* ]]
  # wrangler's own output must still be streamed (to stderr).
  [[ "$stderr" == *"Attempting to login via OAuth"* ]]
}

@test "login: propagates wrangler's exit code on failure" {
  export LOGIN_MODE=fail
  run bash "$INIT_SH" login
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# setup: deploy URL extraction + RESULT format
# ---------------------------------------------------------------------------

@test "setup: full success emits RESULT with endpoint and 32-hex token" {
  run --separate-stderr bash "$INIT_SH" setup
  [ "$status" -eq 0 ]
  local re='RESULT endpoint=https://pubifact\.test-account\.workers\.dev token=[0-9a-f]{32}'
  [[ "$output" =~ $re ]]
}

@test "setup: extracts the workers.dev URL from deploy output into config" {
  run bash "$INIT_SH" setup
  [ "$status" -eq 0 ]
  [ "$(json_get "$CFG" endpoint)" = "https://pubifact.test-account.workers.dev" ]
}

# ---------------------------------------------------------------------------
# setup: subdomain handling
# ---------------------------------------------------------------------------

@test "setup: subdomain needed without --subdomain → exit 11 + ACTION_REQUIRED subdomain" {
  export DEPLOY_MODE=need-subdomain
  run bash "$INIT_SH" setup
  [ "$status" -eq 11 ]
  [[ "$output" == *"ACTION_REQUIRED subdomain: "* ]]
}

@test "setup: --subdomain retries deploy with stdin feed and succeeds" {
  export DEPLOY_MODE="need-subdomain:ok"
  run bash "$INIT_SH" setup --subdomain myname
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT endpoint="* ]]
  # Two deploy invocations recorded (initial + retry).
  [ "$(grep -c ' deploy' "$NPX_LOG")" -eq 2 ]
}

@test "setup: --subdomain retry also fails → exit 11 + ACTION_REQUIRED subdomain-manual" {
  export DEPLOY_MODE="need-subdomain:need-subdomain"
  run bash "$INIT_SH" setup --subdomain myname
  [ "$status" -eq 11 ]
  [[ "$output" == *"ACTION_REQUIRED subdomain-manual: https://dash.cloudflare.com/?to=/:account/workers/onboarding"* ]]
}

# ---------------------------------------------------------------------------
# setup: bucket handling
# ---------------------------------------------------------------------------

@test "setup: R2 not enabled → exit 12 + ACTION_REQUIRED enable-r2" {
  export BUCKET_MODE=no-r2
  run bash "$INIT_SH" setup
  [ "$status" -eq 12 ]
  [[ "$output" == *"ACTION_REQUIRED enable-r2: "* ]]
}

@test "setup: bucket already exists is treated as success" {
  export BUCKET_MODE=exists
  run bash "$INIT_SH" setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT endpoint="* ]]
}

# ---------------------------------------------------------------------------
# setup: multiple accounts
# ---------------------------------------------------------------------------

@test "setup: multiple accounts → exit 13 + ACTION_REQUIRED choose-account with account list" {
  export DEPLOY_MODE=multi-account
  run bash "$INIT_SH" setup
  [ "$status" -eq 13 ]
  [[ "$output" == *"ACTION_REQUIRED choose-account: "* ]]
  [[ "$output" == *"Personal=abc123abc123"* ]]
  [[ "$output" == *"Work=def456def456"* ]]
}

# ---------------------------------------------------------------------------
# config write
# ---------------------------------------------------------------------------

@test "config: parseable by publish.sh's json_get and has 600 perms" {
  run bash "$INIT_SH" setup
  [ "$status" -eq 0 ]
  [ -f "$CFG" ]
  [ "$(json_get "$CFG" endpoint)" = "https://pubifact.test-account.workers.dev" ]
  local tok
  tok="$(json_get "$CFG" token)"
  [[ "$tok" =~ ^[0-9a-f]{32}$ ]]
  local perms
  perms="$(stat -f '%Lp' "$CFG" 2>/dev/null || stat -c '%a' "$CFG")"
  [ "$perms" = "600" ]
}

@test "config: refuses to overwrite a different endpoint without --force (exit 13)" {
  write_config "https://other.example.workers.dev" "oldtok"
  run bash "$INIT_SH" setup
  [ "$status" -eq 13 ]
  [[ "$output" == *"--force"* ]]
  # Config untouched.
  [ "$(json_get "$CFG" endpoint)" = "https://other.example.workers.dev" ]
  [ "$(json_get "$CFG" token)" = "oldtok" ]
}

@test "config: --force overwrites a different endpoint" {
  write_config "https://other.example.workers.dev" "oldtok"
  run bash "$INIT_SH" setup --force
  [ "$status" -eq 0 ]
  [ "$(json_get "$CFG" endpoint)" = "https://pubifact.test-account.workers.dev" ]
  [ "$(json_get "$CFG" token)" != "oldtok" ]
}

@test "config: --no-token omits the token key, skips secret put, RESULT token=none" {
  run bash "$INIT_SH" setup --no-token
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT endpoint=https://pubifact.test-account.workers.dev token=none"* ]]
  [ -z "$(json_get "$CFG" token)" ]
  run grep ' secret put' "$NPX_LOG"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------

@test "verify: endpoint never answers → exit 14, config kept" {
  export CURL_MODE=all-down
  run bash "$INIT_SH" setup
  [ "$status" -eq 14 ]
  [[ "$output" == *"config is saved"* ]]
  # Config not rolled back.
  [ "$(json_get "$CFG" endpoint)" = "https://pubifact.test-account.workers.dev" ]
}

@test "verify: sends Bearer token with the test upload" {
  run bash "$INIT_SH" setup
  [ "$status" -eq 0 ]
  grep -q 'Authorization: Bearer' "$CURL_LOG"
}

# ---------------------------------------------------------------------------
# no-arg mode + flags
# ---------------------------------------------------------------------------

@test "no-arg: not logged in → exit 10, setup never runs" {
  export WHOAMI_MODE=not-logged-in
  run bash "$INIT_SH"
  [ "$status" -eq 10 ]
  run grep ' deploy' "$NPX_LOG"
  [ "$status" -ne 0 ]
}

@test "no-arg: logged in → runs setup through to RESULT" {
  run bash "$INIT_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT endpoint=https://pubifact.test-account.workers.dev"* ]]
}

@test "no-arg: already set up → exit 0 without deploying" {
  write_config "https://pubifact.test-account.workers.dev" "tok123"
  run bash "$INIT_SH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already set up"* ]]
  run grep ' deploy' "$NPX_LOG"
  [ "$status" -ne 0 ]
}

@test "setup: --worker-src runs wrangler in the given directory" {
  local src="$BATS_TEST_TMPDIR/my-worker"
  mkdir -p "$src"
  printf '{ "name": "pubifact" }\n' >"$src/wrangler.jsonc"
  run bash "$INIT_SH" setup --worker-src "$src"
  [ "$status" -eq 0 ]
  grep -q "^$src :: " "$NPX_LOG"
}

@test "setup: --worker-src without wrangler.jsonc → exit 13" {
  local src="$BATS_TEST_TMPDIR/empty-dir"
  mkdir -p "$src"
  run bash "$INIT_SH" setup --worker-src "$src"
  [ "$status" -eq 13 ]
  [[ "$output" == *"wrangler.jsonc"* ]]
}

@test "unknown argument → exit 13 + usage" {
  run bash "$INIT_SH" setup --bogus
  [ "$status" -eq 13 ]
  [[ "$output" == *"usage:"* ]]
}
