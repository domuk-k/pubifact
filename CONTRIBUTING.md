# Contributing to pubifact

## Dev setup

**Worker (TypeScript, Cloudflare Workers):**

```bash
cd worker && npm install
```

**Bash tooling (macOS):**

```bash
brew install shellcheck shfmt bats-core
```

## Verification commands

Run these before submitting a PR:

```bash
# Worker: lint + typecheck + tests
cd worker && npm run check

# Skill scripts: static analysis
shellcheck skills/pubifact/*.sh

# Skill scripts: formatting check
shfmt -d -i 2 -ci skills/pubifact

# Bash integration tests
bats tests/
```

CI runs the same commands on every push (see `.github/workflows/ci.yml`).

## Project layout

```
worker/          Cloudflare Worker backend (TypeScript, wrangler 4)
skills/pubifact/ Agent skill client (publish.sh, init.sh, SKILL.md)
tests/           bats integration tests for the skill scripts
```

## Commit convention

[Conventional commits](https://www.conventionalcommits.org/). Scope is the
changed area — not a feature name:

| Scope | When |
|-------|------|
| `worker` | Anything in `worker/` |
| `skill` | Anything in `skills/pubifact/` |
| `docs` | README, DESIGN, ROADMAP, this file |
| `ci` | `.github/workflows/` |
| `tests` | `tests/` |

Examples: `fix(worker): handle empty body`, `feat(skill): read config.json`,
`docs: update install instructions`.

## Versioning

Single repo-level SemVer, one git tag per release.

- **Major** — breaking change to the `POST /up` / `GET /:key` API contract, or
  to the `publish.sh` CLI contract (arguments, exit codes, stdout format). This
  matters because self-hosters' skill and worker versions can drift; a major bump
  is the signal to update both sides together.
- **Minor** — new functionality, backwards-compatible.
- **Patch** — bug fixes, docs, CI.

No npm publishing — the version tracks the repo state only.

## Release procedure

1. Move `## [Unreleased]` entries in `CHANGELOG.md` into a new `## [X.Y.Z] - YYYY-MM-DD` section.
2. Bump `version` in `worker/package.json` to match.
3. Commit: `chore: release vX.Y.Z`.
4. Tag: `git tag vX.Y.Z`.
5. Push commit + tag: `git push && git push --tags`.

CI's `release.yml` workflow picks up the tag and creates the GitHub Release.

## CHANGELOG

Add an entry under `## [Unreleased]` for every user-facing change (new behavior,
fixed bug, changed CLI contract). Internal refactors and CI changes don't need
an entry, but a one-liner is welcome.

## Pull requests

- Keep PRs small and focused — one logical change per PR.
- CI must be green before merge.
- See the PR template for the checklist.

---

Be kind and assume good faith. This is a small project; the maintainer reserves
the right to close PRs that don't fit the direction without extended debate. If
you're unsure whether something is in scope, open an issue first.
