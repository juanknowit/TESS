# Releasing TESS

Releases are built and published by GitHub Actions ([`.github/workflows/build.yml`](.github/workflows/build.yml)). Every push and pull request runs the tests (**Test**) and builds an unsigned installer (**Build TESS**), attached to the run as an artifact so you can try it before releasing. Only the **Release** job can see the signing certificate or publish.

## Cut a release

1. Set the version in `Resources/Info.plist`: `CFBundleShortVersionString` (numbers only, e.g. `0.9.1`) and `TESSDisplayVersion` (what Settings shows, e.g. `0.9.1 beta`) and `TESSVersion` (the full version the updater compares, e.g. `0.9.1-beta`).
2. In `CHANGELOG.md`, move the items under **[Unreleased]** into a new section, `## [0.9.1-beta] — YYYY-MM-DD`, and update the links at the bottom.
3. Commit and merge to `main`.
4. Publish, in either of two ways:
   - **From GitHub:** Actions › **Build** › **Run workflow**, type the version (e.g. `0.9.1-beta`) in *Publish a release with this version*, and press **Run workflow**. The workflow creates the `v0.9.1-beta` tag itself.
   - **From the command line:** `git tag v0.9.1-beta && git push origin v0.9.1-beta`

The workflow then:

- builds a universal (Apple silicon + Intel) `TESS.app` stamped with the version and the run number as build number
- signs it (see below)
- packs `TESS-<version>.dmg` (drag-to-Applications installer), `TESS-<version>.zip` and `SHA256SUMS.txt`
- publishes a GitHub release named **TESS 0.9.1 beta**, with notes taken from that version's CHANGELOG section plus install instructions

Versions containing a `-` (`v0.9.1-beta`, `v1.0.0-rc.1`) are published as **pre-releases**. A plain tag like `v1.0.0` is a full release.

## Signing

macOS ties permissions (Microphone, Screen Recording, Accessibility, Automation…) to the app's code signature. All releases must therefore be signed with the **same** certificate, or users lose their permissions when they update.

The workflow picks the first of these that is configured as a repository secret (**Settings › Secrets and variables › Actions**):

| Secrets | Result |
|---|---|
| `DEVELOPER_ID_P12`, `DEVELOPER_ID_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Signed with your Developer ID, hardened runtime, notarised and stapled. Opens without any warning. |
| `TESS_SIGNING_P12`, `TESS_SIGNING_PASSWORD` | Signed with the self-signed **TESS Signing** certificate. Users click **Open Anyway** once on first launch. |
| none | Ad-hoc signed. Fine for pull-request builds; **tag builds refuse to publish**. |

`*_P12` secrets hold the certificate and private key as a base64-encoded `.p12` file (`base64 -i certificate.p12 | pbcopy`).

**Keep a backup of the TESS Signing `.p12` and its password somewhere safe** (a password manager). GitHub secrets can't be read back, and a new certificate would reset every user's permissions once.

### Moving to a Developer ID later

1. Join the [Apple Developer Program](https://developer.apple.com/programs/).
2. In Xcode › Settings › Accounts › Manage Certificates, create a **Developer ID Application** certificate, then export it from Keychain Access as a `.p12` with a password.
3. Create an app-specific password at [account.apple.com](https://account.apple.com) › Sign-In and Security.
4. Add the five `DEVELOPER_ID_*` / `APPLE_*` secrets. Your Team ID is shown at [developer.apple.com/account](https://developer.apple.com/account) › Membership details.

The next tag is then notarised automatically and the release notes drop the "Open Anyway" step. Switching certificates changes the signature once, so tell users in that release's notes that macOS will ask for permissions again.

## Building an installer locally

```bash
UNIVERSAL=1 TESS_VERSION=0.9.1-beta ./build.sh
scripts/make-dmg.sh build.noindex/TESS.app dist/TESS-0.9.1-beta.dmg "TESS 0.9.1 beta"
```

`make-dmg.sh` installs [dmgbuild](https://github.com/dmgbuild/dmgbuild) with pip if needed. The window artwork is `Resources/dmg/background.png` (640×420) and `background@2x.png`, and the layout is in `scripts/dmg-settings.py`.
