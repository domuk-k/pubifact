# Security

## Supported versions

The latest commit on `main` (and the most recent tagged release) is supported.
Older versions are not patched.

## Reporting a vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/domuk-k/pubifact/security/advisories/new)
to report confidentially.

Please include: what you found, steps to reproduce, and your assessment of
impact. You'll get an acknowledgement within a few days.

## Trust model

pubifact hosts **arbitrary active HTML by design** — published pages can contain
JavaScript (that is the point; see [DESIGN.md](DESIGN.md)). Reporting that
"JS runs on a published page" is not a vulnerability report.

**In scope:**

- Bypass of the per-link password gate (a password-protected page reachable
  without the correct password).
- Bypass of the `UPLOAD_TOKEN` bearer check (uploading to an instance that has
  `UPLOAD_TOKEN` set, without providing the correct token).
- Any other unintended access-control bypass.

**Not in scope:**

- Arbitrary JS execution on a published page (by design; same trust model as
  surge, neocities, CodePen).
- Content hosted by other users' instances (each instance is independently
  operated; we don't run a shared host).
