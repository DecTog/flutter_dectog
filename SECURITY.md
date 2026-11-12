# Security policy

AdTo handles install attribution, API keys and webhook secrets for the apps
that use it, so security reports get priority over everything else.

## Reporting a vulnerability

Please report privately. Do not open a public issue.

- **Preferred:** GitHub's private vulnerability reporting: the **Security** tab
  of this repository, then **Report a vulnerability**.
- **Or email** hello@adto.app with `SECURITY` in the subject.

Include what you found, how to reproduce it, the affected version or commit,
and the impact you expect. A proof of concept helps; please do not access or
modify data that is not yours, and do not run denial-of-service tests against
the hosted service.

## What to expect

| Step | Target |
|---|---|
| Acknowledgement | within 48 hours |
| First assessment and severity | within 5 working days |
| Fix or mitigation for a confirmed high or critical issue | within 30 days, sooner when exploited |

We will keep you informed, credit you in the release notes unless you prefer
otherwise, and agree a disclosure date with you once a fix is available.

## Scope

In scope: this repository (the Dart package and its Kotlin and Swift plugin
code), the server it talks to
([ad-to/adto](https://github.com/ad-to/adto)), and the hosted service at
`adto.app`, `dashboard.adto.app`, `api.adto.app` and `*.adto.app`.

Of particular interest: leaking the API key or device data beyond what the
documentation says is sent, request-signature weaknesses, the SDK acting on a
URL that is not an AdTo link (for example an OAuth callback), collection that
continues after `setEnabled(false)`, and pasteboard reads that the
documentation does not describe.

Out of scope: findings that need a compromised device or a malicious app on the
user's phone, rate limits on public pages beyond the documented ones, missing
security headers without a demonstrated impact, and reports produced only by
automated scanners.

## Dependencies and builds

- The example app commits its `pubspec.lock`, so its builds are reproducible; the package does
  not, since every app resolves its own versions.
- Dependabot proposes updates every week for the package, the companion `flutter_adto_adid`,
  the example app, the Android plugin's Gradle dependencies and the GitHub Actions; CI runs on
  each proposal and prints `flutter pub outdated` on every run.
- Every GitHub Action is pinned to a commit SHA.
- Releases are published from CI on a version tag that must match `pubspec.yaml`,
  `lib/src/version.dart` and `CHANGELOG.md`, with pub.dev's OIDC publishing: no long-lived token
  exists ([RELEASING.md](RELEASING.md)).

## Supported versions

Fixes land on `main` and ship in the next release on
[pub.dev](https://pub.dev/packages/flutter_adto).
