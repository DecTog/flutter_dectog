# Releasing flutter_adto

flutter_adto is on pub.dev (1.0.0, published 2026-11-04). Versions follow
semantic versioning: a breaking change to the public API needs a major
version. CI runs `flutter pub publish --dry-run` on every push so the package
stays publishable.

## Every release

1. Bump the version in all four places. `test/version_test.dart` fails CI when
   they disagree:
   - `pubspec.yaml` `version:`
   - `lib/src/version.dart` `packageVersion`
   - `ios/flutter_adto.podspec` `s.version`
   - a new `## [x.y.z] - YYYY-MM-DD` entry at the top of `CHANGELOG.md`
   On a major bump, also update the `flutter_adto: ^x.0.0` line in `README.md`,
   the install snippet in `adto/apps/web/public/SKILL.md` and the docs site's
   `sdk/installation` page.
2. Check locally, with the server repository checked out next to this one:
   ```bash
   tool/sync_wire_fixtures.sh --check
   dart format --output=none --set-exit-if-changed lib test example/lib
   flutter analyze
   flutter test
   flutter pub publish --dry-run
   ```
3. Merge to `main` with CI green.
4. Tag the merge commit and push the tag:
   ```bash
   git tag v1.2.3 && git push origin v1.2.3
   ```
   `.github/workflows/publish.yml` checks that the tag equals the pubspec,
   `version.dart` and CHANGELOG versions, then publishes through pub.dev's
   GitHub OIDC flow. No pub.dev credential is stored in the repository.
5. Create a GitHub release from the tag with the CHANGELOG entry as notes.

## First publish (release day only)

pub.dev enables automated publishing only for a package that already exists, so
the first version goes out by hand. flutter_adto 1.0.0 is out;
`flutter_adto_adid` is not on pub.dev yet (step 4).

1. `flutter pub publish` from a clean checkout of the tagged commit, signed in as
   the publisher account.
2. On pub.dev, package admin page: set the publisher, then enable
   "Automated publishing" from GitHub Actions for `ad-to/flutter_adto`, tag
   pattern `v{{version}}`, and require the `pub.dev` environment.
3. In the GitHub repository settings, create the `pub.dev` environment and add
   required reviewers so a tag alone cannot publish.
4. Then the companion package `flutter_adto_adid`, which depends on
   the published flutter_adto: `tool/publish_adid.sh` publishes it from a
   copy outside the repository (`packages/.pubignore` keeps it out of the
   flutter_adto archive, and pub would apply that file to it too). Its
   version moves with flutter_adto's: `packages/flutter_adto_adid/pubspec.yaml`,
   its podspec and its CHANGELOG.
