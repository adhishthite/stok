# GitHub automation and local releases

Stok is open source under Apache-2.0. Code and Sparkle releases both live in the
public repository `adhishthite/stok`. No release tag or asset is published yet.
Tags, releases, and pushes need the owner's instruction.

## Continuous integration

`.github/workflows/lint.yml` is the fast pull-request check. It runs on Linux on
every pull-request push and every push to main: swift-format lint with the Swift
6.4 image, the license file and header checks, shell syntax, Ruff, the Python
regression tests, and actionlint. It needs no Xcode and takes a few minutes.

`.github/workflows/ci.yml` is the full build and XCTest run, using macOS 26 and
Xcode 26.6. It runs on pull requests and pushes to main that change a build input
(`Sources`, `Tests`, `Resources`, `Scripts`, `Tools`, `Config`, `project.yml`,
`Makefile`, or the workflows), and on manual requests. The repository is public,
so hosted runner minutes are free. Every run validates tooling and runs `make
check` under the documented 420-second hosted deadline. The Sparkle package
checkout is cached between runs, keyed on `project.yml`. Only manual runs also
package a development ZIP, bounded at 240 seconds and retained for 14 days. These
are development artifacts, not signed public releases. Test results are uploaded
only when a run fails, and kept for three days.

## Approved release route

Build, sign, and notarize locally with the existing Developer ID identity,
`StokNotary` profile, and Sparkle Keychain account `com.adhishthite.stok`. No signing
credential export or upload is authorized or needed. The manual release workflow
now performs readiness checks only. It has no signing secrets or publication step.

The helper uses one repository, `adhishthite/stok`. The source must be a clean
main checkout at the fetched origin/main. The release tag must resolve to that
commit. The repository must be public for anonymous Sparkle downloads. Feed URLs
use credential-free HTTPS on github.com in the same repository.

Before local staging, set these nonsecret inputs:

```sh
export STOK_RELEASE_REPOSITORY=adhishthite/stok
export STOK_RELEASE_TAG=v0.1.0
export NOTARY_PROFILE=StokNotary
```

Set `STOK_EXPECTED_TEAM_ID` to the signing team identifier. The release tag must
match `MARKETING_VERSION`; every build requires a new `CURRENT_PROJECT_VERSION`.
Refresh origin/main before the read-only preflight. This configuration does not
authorize creating a tag or publishing a release.

1. Run the repository checks and commit/push the exact source. Wait for its CI.
2. Use `make distribute`, `make notarize-app`, and `make notarize-dmg` with the
   bounded, resumable procedure in DISTRIBUTION.md. Preserve each tested build.
   `STOK_UPDATE_FEED_URL` may override the production feed for a validation build.
3. Run `python3 Scripts/ci/release.py stage-assets` under a 120-second supervisor.
   It verifies the prebuilt artifacts and writes `build/release-assets/` with
   Stok.dmg, Stok.zip, appcast.xml, checksums.txt, and a local release manifest.
   It creates no draft or tag and uploads nothing. Existing nonempty stage
   directories are refused; preserve them before staging another build.
4. Review exact filenames, hashes, version, feed, and release notes with the owner.
   Only after approval may the named assets be uploaded and published. Never
   publish a recovery bundle, logs, or application data.
5. Verify anonymous downloads and the real installed Sparkle update separately.
   See UPDATE_FEED.md for validation-feed and tamper-test requirements.

The production feed is
`https://github.com/adhishthite/stok/releases/latest/download/appcast.xml`.
Archive URLs use the exact release tag. The app never includes a GitHub token.

## Optional authorized draft preparation

`prepare` and `resume` require the explicit nonsecret
`STOK_RELEASE_DRAFT_AUTHORIZATION` value
`REPOSITORY:TAG:COMMIT`, where COMMIT is the checked-out HEAD. It must match the
request exactly. Set it only
after owner authorization for that specific draft/tag. The helper never publishes.
`prepare` builds and notarizes; do not use it to upload already reviewed staged
assets because it would prepare another build. Local `stage-assets` is the normal
path for the current acceptance work.

Saved notarization IDs remain under `build/notary/`; an unfinished Apple review
must reuse its submission. Recover an ambiguous upload with the documented
`Scripts/notarize.py --submission` procedure, never by retrying an upload blindly.
Recovery checks the recorded repository, source commit, tag, build, and feed identities.

## Validation

`make check` includes release regression tests. `make check-ci` validates workflow
syntax, signing helper types, and Python lint. The legacy signing helper remains
unused by the approved local route; it must not be invoked to export credentials.
