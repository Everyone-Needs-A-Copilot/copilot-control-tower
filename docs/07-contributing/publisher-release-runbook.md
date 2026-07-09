# Publisher release runbook

This is the release-owner path for producing a macOS artifact that Gatekeeper
can trust. It is intentionally separate from the Admin/IT standup path in
[`../06-deployment/standup-runbook.md`](../06-deployment/standup-runbook.md):
the publisher signs and notarizes the app; an administrator deploys an
already-built artifact plus org policy.

## Repo boundary

Admin mode is part of this repository because it is part of the Control Tower
product: the same open-source app that supervises `cc` also gives IT a guided
standup, seed generation, repo/team-grant scaffolding, and preflight surface.

Publisher setup also lives in this repository, but only as release-owner
tooling under `scripts/` and `docs/07-contributing/`. It is not a customer
feature, not an Admin-mode window, and not part of the normal app surface.
Keeping it here lets the publisher UI stay close to the signing scripts and CI
workflow without creating a separate product or giving fleet administrators
release-signing authority.

For the full role split and handoff, see
[`../reference/publisher-admin-experience.md`](../reference/publisher-admin-experience.md).

## Publisher vs. administrator

The **publisher** controls release-signing authority:

- Apple Developer ID Application certificate.
- Apple notarization credential.
- Release workflow secrets.
- Update-manifest signing keys, once production two-of-N custody is assigned.

The **administrator** controls fleet configuration:

- `ecosystem.yml` seed and repo/access scaffolding.
- GitHub team grants that gate repo access (the entitlement spine).
- `AdminContact`, update feed, telemetry collector, and rollout scope.

The same person may wear both hats while dogfooding, but the credentials must
not blur. An admin may need to know the publisher's Team ID to reference in the
org's signed inherited config; the admin should never need the publisher's
Developer ID private key or notarization credential.

## 1. Create the Developer ID Application certificate

Use Apple's official Developer ID certificate flow:

- Apple account help: <https://developer.apple.com/help/account/certificates/create-developer-id-certificates/>
- CSR help: <https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/>

In Keychain Access:

1. Open **Keychain Access** from `/Applications/Utilities`.
2. Choose **Keychain Access > Certificate Assistant > Request a Certificate
   From a Certificate Authority**.
3. Enter the Apple Developer account email.
4. Use a clear common name, for example `Pablo Developer ID Application`.
5. Leave the CA Email Address field empty.
6. Choose **Saved to disk**.
7. Save the `.certSigningRequest` file.

In Apple Developer:

1. Go to **Certificates, Identifiers & Profiles > Certificates**.
2. Create a new **Developer ID** certificate.
3. Choose **Developer ID Application** for this app.
4. When asked for the Developer ID certificate intermediary, choose
   **G2 Sub-CA (Xcode 11.4.1 or later)**.
5. Upload the `.certSigningRequest` file.
6. Download the generated `.cer`.
7. Double-click the `.cer` to install it into the login keychain.

Do not choose **Previous Sub-CA** for a new Control Tower release path. Apple's
PKI page lists Developer ID G1 as the older intermediate and Developer ID G2 as
the current longer-lived intermediate:
<https://www.apple.com/certificateauthority/>.

## 2. Install the G2 intermediate if needed

If the new certificate appears as untrusted in Keychain Access, install Apple's
**Developer ID - G2** intermediate from:

<https://www.apple.com/certificateauthority/>

After installing the intermediate, leave certificate trust settings at **Use
System Defaults**. Do not fix trust by setting the app certificate to **Always
Trust**; that masks a chain problem instead of proving the local signing path
is correct.

In **Keychain Access > login > My Certificates**, the Developer ID Application
certificate must show a disclosure arrow with a private key underneath it. If
there is no private key, the certificate cannot sign releases on this Mac; the
CSR was generated from a different keychain/private key than the installed
certificate.

Verify macOS sees a usable signing identity:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Save the quoted identity string. It should look like:

```text
Developer ID Application: Your Name (TEAMID)
```

## 3. Publisher setup checklist

Complete this checklist before opening **Publisher Setup.app**. The app is
intentionally small: it configures this repo once the Apple-side material
already exists; it does not create Apple account credentials for you.

- **Apple Developer membership is active.** The Team ID is visible in Apple
  Developer account membership details.
- **Developer ID Application certificate is installed and trusted.** Use the
  G2 Sub-CA certificate, install Apple's **Developer ID - G2** intermediate if
  Keychain shows the cert as untrusted, and confirm the certificate has a
  private key under it in **Keychain Access > login > My Certificates**.
- **The signing identity is visible to macOS.**

  ```bash
  security find-identity -v -p codesigning | grep "Developer ID Application"
  ```

- **You know which Apple ID owns notarization for this Team ID.** This is the
  Apple Developer account email, not something stored in the Developer ID cert.
  The certificate exposes the Team ID and name; it does not expose the Apple ID
  email.
- **You have generated an Apple app-specific password from Apple.** Do not use
  your normal Apple ID password. Do not use a new password invented by a
  password manager. `notarytool` needs a password that Apple generated and
  registered for your account.

  Create it at <https://account.apple.com>:

  1. Sign in with the Apple Developer Apple ID for this Team ID.
  2. Open **Sign-In and Security**.
  3. Open **App-Specific Passwords**.
  4. Generate a password named something like `Control Tower Notary`.
  5. Keep the generated value available only long enough to paste it into
     **Publisher Setup.app**.

  Apple documents app-specific passwords here:
  <https://support.apple.com/en-us/102654>

After this checklist, continue to the setup app.

## 4. Bootstrap this repo's publisher environment

Once the certificate is installed and trusted, use the publisher setup UI
instead of hand-writing local env. From Finder, double-click the repo-local app
bundle:

```text
Publisher Setup.app
```

Or launch the same UI from Terminal without Terminal owning the form input:

```bash
open "Publisher Setup.app"
```

The UI:

- opens with a prerequisite checklist
- provides **Learn More** detail screens for Apple Developer membership,
  Developer ID certificates, the Developer ID - G2 intermediate, and
  app-specific passwords
- detects the installed `Developer ID Application` identity
- extracts the Team ID from the identity
- stores a `ct-notary` Keychain profile through `xcrun notarytool`
- writes `.env.release.local` with mode `600`
- avoids accepting the app-specific password as a shell argument
- clears the app-specific password from the form after setup
- replaces the form with a success screen that can run build/sign/notarize
  directly
- shows publishing progress and keeps a copyable log
- ends on an Admin handoff screen once the signed/notarized artifact exists
- replaces the form with a failure screen that provides copyable details and
  recovery actions

The app wrapper compiles the SwiftUI utility into `.copilot/publisher-setup/`
and runs that local binary. `.copilot/` is ignored by git. The older
`scripts/publisher-setup.command` fallback remains available, but double-clicking
`.command` files opens Terminal on macOS; prefer the `.app` bundle for normal
publisher setup.

The shell bootstrap remains as a fallback for headless or CI-like local use:

```bash
./scripts/setup-publisher.sh --apple-id "you@example.com"
```

The fallback script:

- detects the installed `Developer ID Application` identity
- extracts the Team ID from the identity
- stores a `ct-notary` Keychain profile through `xcrun notarytool`
- writes `.env.release.local` with mode `600`
- avoids accepting the app-specific password as a command-line argument

If multiple Developer ID Application identities exist, the script asks which
one to use. If the notary profile already exists and only the env file needs
to be refreshed, run:

```bash
./scripts/setup-publisher.sh --skip-notary --force
```

Then load the generated file:

```bash
source .env.release.local
```

The manual steps below are here as a fallback and to document what the script
does.

## 5. Store the notarization credential manually

For a local publisher machine, prefer a Keychain profile so no Apple password
or API private key is written into this repo:

```bash
xcrun notarytool store-credentials "ct-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

The `--password` value above must be the Apple-generated app-specific password
from the checklist, not the normal Apple ID password and not a password-manager
generated random string.

For CI, use App Store Connect API-key secrets instead of a local keychain
profile. The existing release workflow expects:

- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_KEY_ISSUER`
- `APPLE_NOTARY_KEY_PATH`

Apple's current notarization tooling is `notarytool`; see:
<https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool>

## 6. Create a local-only release environment file manually

This repo intentionally does not commit release credentials. `.gitignore`
excludes `.env` and `.env.*`, so a local release file may exist without being
tracked.

Create `.env.release.local`:

```bash
export CT_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export APPLE_SIGNING_IDENTITY="$CT_SIGN_IDENTITY"
export CT_NOTARY_KEYCHAIN_PROFILE='ct-notary'
```

Protect and load it:

```bash
chmod 600 .env.release.local
source .env.release.local
```

Do not commit `.env.release.local`, `.p12` files, `.p8` files, app-specific
passwords, or certificate export passwords.

## 7. Build, sign, notarize, and staple locally

After Publisher Setup creates the local env file and notary profile, use the
app's **Build, Sign, and Notarize** button. The app runs the same release
commands below, shows progress, and keeps a copyable log for failures or
release notes.

Use the terminal commands only as a fallback for debugging or headless
publisher machines.

The local build has one important gotcha: the `copilot` CLI may also be
installed as `cc`, which can shadow the system C compiler. Force the real C
compiler when building the Tauri app:

```bash
PATH="/usr/bin:$PATH" CC=/usr/bin/cc npm run tauri build
```

The repo's signing and notarization scripts read the environment; they do not
hardcode credentials:

- [`../../scripts/sign.sh`](../../scripts/sign.sh)
- [`../../scripts/notarize.sh`](../../scripts/notarize.sh)

Run the explicit signing pass:

```bash
./scripts/sign.sh "src-tauri/target/release/bundle/macos/Copilot Control Tower.app"
```

Then submit, staple, and validate:

```bash
./scripts/notarize.sh \
  "src-tauri/target/release/bundle/macos/Copilot Control Tower.app" \
  "src-tauri/target/release/bundle/dmg/Copilot Control Tower.dmg"
```

The result is a publisher-produced artifact suitable for admin/fleet testing.
It is not, by itself, a complete `stable` self-update promotion until the
update-manifest signing custody decision is resolved.

## 8. Promote the proven path into CI

After the local path is proven, configure the GitHub `release` environment
secrets used by [`../../.github/workflows/release.yml`](../../.github/workflows/release.yml):

- `APPLE_SIGNING_IDENTITY`
- `APPLE_CERTIFICATE`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_KEY_ISSUER`
- `APPLE_NOTARY_KEY_PATH`

The workflow is tag-triggered (`v*`) and should remain owner-gated. Do not use
CI to discover missing credentials for the first time; prove them locally first,
then transfer only the minimum required secrets into the release environment.

## 9. Stable-promotion caveat

Developer ID signing and Apple notarization prove that this Team ID built the
app and that Apple accepted the submitted artifact. Control Tower's self-update
path adds a second release-trust gate: the update manifest must be signed by
the compiled-in update-signing roots.

Production two-of-N custody is documented separately in
[`../06-deployment/two-of-n-custody-runbook.md`](../06-deployment/two-of-n-custody-runbook.md)
and [`../05-security/signing-custody.md`](../05-security/signing-custody.md).
Until real production keys and custodians are assigned, treat local
signing/notarization as "artifact is ready for admin validation," not "stable
self-update promotion is fully operational."
