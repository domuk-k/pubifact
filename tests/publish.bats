#!/usr/bin/env bats
# Tests for skills/pubifact/publish.sh
#
# Requires: bats-core >= 1.5.0, stub curl at tests/stubs/curl
bats_require_minimum_version 1.5.0

PUBLISH_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/pubifact/publish.sh"

setup() {
  # Prepend our stub directory so stub curl takes priority.
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

  # Isolate config from the real user config.
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"

  # Clear any env vars that might bleed in from the real environment.
  unset PUBIFACT_ENDPOINT PUBIFACT_TOKEN PUBIFACT_PASSWORD

  # Create a test file fixture.
  mkdir -p "$BATS_TEST_TMPDIR"
  printf '<html><body>test</body></html>\n' >"$BATS_TEST_TMPDIR/page.html"

  # Log file for curl invocation recording (cleared per test).
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  rm -f "$CURL_LOG"

  # Default mode: successful.
  export CURL_MODE="ok"
}

# ---------------------------------------------------------------------------
# json_get helper (tested by sourcing the relevant lines)
# ---------------------------------------------------------------------------

@test "json_get extracts endpoint from config fixture" {
  mkdir -p "$XDG_CONFIG_HOME/pubifact"
  printf '{"endpoint":"https://my.instance.dev","token":"tok123"}\n' \
    >"$XDG_CONFIG_HOME/pubifact/config.json"

  # Source just the json_get function and CONFIG resolution from publish.sh.
  # We test it by running publish.sh with the config in place and confirming
  # the endpoint is used (stub curl in ok mode hits /up → success).
  run --separate-stderr bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 0 ]
  # stdout should be the fake URL from the stub (ok mode, /up path).
  [ "$output" = "https://example-instance.workers.dev/abc123" ]
}

@test "json_get returns empty for missing key" {
  mkdir -p "$XDG_CONFIG_HOME/pubifact"
  printf '{"endpoint":"https://my.instance.dev"}\n' \
    >"$XDG_CONFIG_HOME/pubifact/config.json"

  # token is not in config → TOKEN should be empty.
  # With CURL_MODE=ok the endpoint returns 200, so Bearer header should NOT appear.
  run bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 0 ]
  # No "Authorization: Bearer" in curl log because token is absent.
  if [ -f "$CURL_LOG" ]; then
    run grep -q "Authorization: Bearer" "$CURL_LOG"
    [ "$status" -ne 0 ]
  fi
}

@test "env var PUBIFACT_ENDPOINT beats config file" {
  mkdir -p "$XDG_CONFIG_HOME/pubifact"
  # Config says one endpoint; env var says another.
  printf '{"endpoint":"https://from-config.workers.dev"}\n' \
    >"$XDG_CONFIG_HOME/pubifact/config.json"

  export PUBIFACT_ENDPOINT="https://from-env.workers.dev"
  run bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 0 ]
  # The URL in CURL_LOG should contain the env var endpoint, not the config one.
  grep -q "from-env.workers.dev" "$CURL_LOG"
  run grep "from-config.workers.dev" "$CURL_LOG"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# no instance configured → init-first: exit 3, point at init.sh, upload nothing
# ---------------------------------------------------------------------------

@test "no endpoint no password exits 3 with init.sh hint, uploads nothing" {
  # No config, no endpoint env var.
  run --separate-stderr bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 3 ]
  # No URL printed — nothing was uploaded anywhere.
  [ -z "$output" ]
  # stderr points the user at one-time setup, never a temporary host.
  [[ "$stderr" == *"no instance configured"* ]]
  [[ "$stderr" == *"init.sh"* ]]
  # curl was never invoked — we don't leak to any anonymous host.
  [ ! -f "$CURL_LOG" ]
}

@test "no endpoint WITH password also exits 3 (no special case)" {
  run bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html" --password "s3cr3t"
  [ "$status" -eq 3 ]
  [ ! -f "$CURL_LOG" ]
}

@test "no endpoint never contacts a third-party host (no tmpfiles)" {
  run --separate-stderr bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [[ "$stderr" != *"tmpfiles"* ]]
  [[ "$stderr" != *"EXPIRES"* ]]
}

# ---------------------------------------------------------------------------
# endpoint 200 → stdout is exactly the URL; Bearer header present when token set
# ---------------------------------------------------------------------------

@test "endpoint 200 stdout is exactly the URL" {
  export PUBIFACT_ENDPOINT="https://my.instance.workers.dev"
  run --separate-stderr bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 0 ]
  [ "$output" = "https://example-instance.workers.dev/abc123" ]
}

@test "Bearer header present in curl args when token configured" {
  export PUBIFACT_ENDPOINT="https://my.instance.workers.dev"
  export PUBIFACT_TOKEN="mytoken123"
  run bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 0 ]
  grep -q "Authorization: Bearer mytoken123" "$CURL_LOG"
}

@test "no Bearer header when no token" {
  export PUBIFACT_ENDPOINT="https://my.instance.workers.dev"
  run bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 0 ]
  # CURL_LOG exists; must not contain Authorization Bearer line.
  run grep "Authorization: Bearer" "$CURL_LOG"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# endpoint errors → exit 4 (auth/size), no fallback anywhere
# ---------------------------------------------------------------------------

@test "endpoint 401 exits 4" {
  export PUBIFACT_ENDPOINT="https://my.instance.workers.dev"
  export CURL_MODE="auth-fail"
  run bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 4 ]
}

@test "endpoint 413 exits 4" {
  export PUBIFACT_ENDPOINT="https://my.instance.workers.dev"
  export CURL_MODE="size-fail"
  run bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 4 ]
}

# ---------------------------------------------------------------------------
# endpoint network failure (000) → exit 1, no fallback (init-first)
# ---------------------------------------------------------------------------

@test "endpoint network failure exits 1 (no fallback host)" {
  export PUBIFACT_ENDPOINT="https://my.instance.workers.dev"
  export CURL_MODE="endpoint-down"
  run --separate-stderr bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 1 ]
  # No temporary link, no third-party host.
  [ -z "$output" ]
  [[ "$stderr" != *"tmpfiles"* ]]
}

# ---------------------------------------------------------------------------
# usage / missing file
# ---------------------------------------------------------------------------

@test "missing file argument exits 2" {
  run bash "$PUBLISH_SH"
  [ "$status" -eq 2 ]
}

@test "nonexistent file exits 2" {
  run bash "$PUBLISH_SH" /tmp/does-not-exist-pubifact-test.html
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# takedown: publish hint + --down mode
# ---------------------------------------------------------------------------

@test "publish surfaces the delete token as a takedown hint on stderr" {
  export PUBIFACT_ENDPOINT="https://my.instance.workers.dev"
  run --separate-stderr bash "$PUBLISH_SH" "$BATS_TEST_TMPDIR/page.html"
  [ "$status" -eq 0 ]
  # stdout stays URL-only even though the body now carries a second line.
  [ "$output" = "https://example-instance.workers.dev/abc123" ]
  [[ "$stderr" == *"--down https://example-instance.workers.dev/abc123 --token dtok0123456789abcdef0123456789ab"* ]]
}

@test "--down without token exits 2" {
  run bash "$PUBLISH_SH" --down "https://my.instance.workers.dev/abc123.html"
  [ "$status" -eq 2 ]
}

@test "--down with valid token takes the page down" {
  run --separate-stderr bash "$PUBLISH_SH" \
    --down "https://my.instance.workers.dev/abc123.html" --token "dtok123"
  [ "$status" -eq 0 ]
  [ "$output" = "taken down" ]
  grep -q -- "-X DELETE" "$CURL_LOG"
  grep -q "Authorization: Bearer dtok123" "$CURL_LOG"
}

@test "--down with wrong token exits 4" {
  export CURL_MODE="auth-fail"
  run bash "$PUBLISH_SH" \
    --down "https://my.instance.workers.dev/abc123.html" --token "wrong"
  [ "$status" -eq 4 ]
}

@test "--down on unknown URL exits 1" {
  export CURL_MODE="gone"
  run bash "$PUBLISH_SH" \
    --down "https://my.instance.workers.dev/zzz.html" --token "dtok123"
  [ "$status" -eq 1 ]
}

@test "--down network failure exits 1" {
  export CURL_MODE="endpoint-down"
  run bash "$PUBLISH_SH" \
    --down "https://my.instance.workers.dev/abc123.html" --token "dtok123"
  [ "$status" -eq 1 ]
}

@test "PUBIFACT_DELETE_TOKEN env var works for --down" {
  export PUBIFACT_DELETE_TOKEN="envtok456"
  run --separate-stderr bash "$PUBLISH_SH" --down "https://my.instance.workers.dev/abc123.html"
  [ "$status" -eq 0 ]
  grep -q "Authorization: Bearer envtok456" "$CURL_LOG"
}
