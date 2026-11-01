# Signing native mail account builds

Reviewed 1 November 2026. The native credential vault (Google authorization state, Microsoft account references, and iCloud/IMAP server credentials) selects the macOS Data Protection
Keychain with `kSecUseDataProtectionKeychain = true`, `kSecAttrSynchronizable = false`, and
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The latter accessibility setting requires the Data
Protection implementation on macOS. Dropping that selection to make an unprovisioned build work would
silently change the storage guarantees. [Apple: accessibility](https://developer.apple.com/documentation/security/ksecattraccessible),
[Apple: selecting the Data Protection Keychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain).

## Minimum authorization

The system derives Data Protection Keychain access from the application's signed entitlements.
Apple requires a provisioning profile to authorize these claims. A Developer ID certificate alone
does not supply that profile. [Apple TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).

`Apps/macOS/App/Altillo.provisioned.entitlements` preserves the four existing hardware/automation
permissions and adds only:

```xml
<key>com.apple.application-identifier</key>
<string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string>
```

The profile supplies the app identifier prefix; `AppIdentifierPrefix` includes the trailing period.
It is normally the team identifier but can differ for historical accounts. The signed value must
match the profile and contain no unresolved build variable. Xcode supplies any normal signing
identity/team entitlements as part of provisioning.

There is no `keychain-access-groups` or `com.apple.security.application-groups` claim in this file.
When neither is requested, the app identifier is its private default Keychain access group. Do not
add a group for other apps, turn on App Sandbox, or change another target's identity to solve this
requirement. [Apple: access group construction](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).

MSAL separately owns its token cache. Its SDK cache configuration uses the bundle identifier as the
private cache group, as documented by `MSALCacheConfig.h` in release 2.17.0; the application does not
duplicate Microsoft tokens into its own vault. A shared MSAL cache/SSO group is not needed here.
[MSAL cache configuration](https://github.com/AzureAD/microsoft-authentication-library-for-objc/blob/2.17.0/MSAL/src/public/configuration/publicClientApplication/cache/MSALCacheConfig.h).

## Local state inspected and configured

The installed official application has bundle ID `me.badia.altillo`, team `9L2TD7KVV9`, and Developer
ID signing. Its current signature has the existing four permissions and no application identifier.
Initially no Altillo macOS profile, nor a suitable macOS wildcard profile, was present locally.

The account already has an unrelated macOS Developer ID profile for another explicit App ID. That
establishes that Developer ID provisioning has been used with this account; that unrelated profile
does not authorize Altillo and must not be copied into it. Other discovered profiles were for iOS.
The existing App ID `me.badia.altillo` was then found through the account's App Store Connect API.
Created **Altillo Developer ID Native Mail**, UUID `1f3026de-69ef-45e8-9722-b2f8c79a7b82`, using the
existing Developer ID certificate whose SHA-1 is `B97D44DCB76A1388E5B560073688EECFA8935F83`.
It is installed under `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` and expires on
1 February 2027. No new signing key, shared Keychain group or unrelated App ID was created.

Local Release settings select this profile and Developer ID; Debug keeps its existing Apple
Development setup. The provisioned Release build passes strict signature, profile App ID/team and
certificate checks and has no debugger entitlement. A small signed QA executable using the exact
Release entitlements successfully added/read/deleted an isolated synthetic Data Protection Keychain
item with `WhenUnlockedThisDeviceOnly`; it never enumerated real credentials.

## Production Developer ID build

1. In the owning Apple Developer account, confirm or register the explicit macOS App ID
   `me.badia.altillo`. Create/download a **Developer ID** provisioning profile for that App ID and
   the certificate used to sign the release. This is an external account action, not something the
   source changes perform. An iOS profile, Mac App Store profile, or another app's profile cannot be
   substituted. Apple documents Developer ID profiles for distribution outside the store.
2. Install the profile in Xcode's provisioning profile directory. Use its exact name or UUID as the
   profile specifier. Keep the profile available to the release runner alongside the signing
   certificate. Treat it as signing material; do not commit a local downloaded profile.
3. Apply the following build settings to the **Altillo application target only**:

   ```text
   DEVELOPMENT_TEAM = 9L2TD7KVV9
   PRODUCT_BUNDLE_IDENTIFIER = me.badia.altillo
   CODE_SIGN_STYLE = Manual
   CODE_SIGN_IDENTITY = Developer ID Application
   CODE_SIGN_ENTITLEMENTS = Apps/macOS/App/Altillo.provisioned.entitlements
   PROVISIONING_PROFILE_SPECIFIER = <exact Altillo Developer ID profile name or UUID>
   ```

   Do not pass the last two settings globally to `xcodebuild`: that would also apply the app ID and
   profile to test bundles and helper targets. With this repository's XcodeGen configuration, make
   the main target's settings use `ALTILLO_MAC_ENTITLEMENTS` and
   `ALTILLO_MAC_PROVISIONING_PROFILE` from `Config/Shared.xcconfig`. Their defaults remain the current
   unprovisioned entitlement file and empty profile. In the ignored `Config/Local.xcconfig`, set:

   ```text
   ALTILLO_MAC_ENTITLEMENTS = Apps/macOS/App/Altillo.provisioned.entitlements
   ALTILLO_MAC_PROVISIONING_PROFILE = <exact Altillo Developer ID profile name or UUID>
   ```

   Installing a profile alone does not select these settings.
   If Debug uses a different signing identity, use the `[config=Release]` variants shown in
   `Config/Local.xcconfig.example`. A Developer ID profile cannot authorize an Apple Development
   certificate; development OAuth needs its own matching development profile.
4. Archive with the existing hardened runtime and embed the profile at
   `Altillo.app/Contents/embedded.provisionprofile`. For manual archive export, add an ExportOptions
   mapping matching the actual release App ID:

   ```xml
   <key>method</key><string>developer-id</string>
   <key>signingStyle</key><string>manual</string>
   <key>teamID</key><string>9L2TD7KVV9</string>
   <key>signingCertificate</key><string>Developer ID Application</string>
   <key>provisioningProfiles</key>
   <dict>
     <key>me.badia.altillo</key>
     <string>EXACT_ALTILLO_DEVELOPER_ID_PROFILE_NAME_OR_UUID</string>
   </dict>
   ```

   `script/release.sh` validates the archived app with `script/check-mail-signing.py`, derives this
   mapping from the embedded profile UUID, and validates the exported app again. Publishing also
   requires both registered provider client IDs. Dry-run/ad-hoc builds do not prove Keychain access.
5. Inspect the exported application's signature, the profile's App ID/platform/expiry and matching
   certificate, and verify the signature before notarization. Do not dump the whole profile into
   release logs: print only the metadata needed for that check. The profile must authorize this
   exact application identifier, have the macOS platform, and support Developer ID distribution to
   all devices. Inspect the final exported app, since export may change the archive's signature.
6. Run `python3 script/check-mail-keychain.py <exported-app> <signing-identity>` to create, read and
   remove a synthetic record using a fresh isolated service name. The release script runs this
   automatically for provisioned builds. It never enumerates or deletes a person's mail credentials.
   Keychain success must precede real OAuth QA. Notarize/package only after the signed test passes.

[Apple TN3125: provisioning and profile location](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles),
[Apple: Developer ID signing](https://developer.apple.com/developer-id/).

## Development and CI

For interactive OAuth development, use an **Apple Development** certificate with a matching macOS
development provisioning profile for the chosen bundle ID, or a correctly provisioned Developer ID
build. Select the provisioned entitlement file only for that target/build. A separate development
bundle ID also changes the Microsoft redirect scheme and requires the corresponding provider
registration. A development profile can be limited to registered Macs; it is not a distribution
profile for other users.

Community/ad-hoc builds keep `Altillo.entitlements`, an empty team, identity `-`, an empty profile
specifier, and empty OAuth client identifiers. They can compile and run the rest of the app. They
cannot validate production Data Protection Keychain access, and must not receive a fabricated app
identifier with an empty prefix. The native-auth and controller suites inject memory vaults,
synthetic drivers and providers, so they never require OAuth UI or the real Keychain. A green ad-hoc
suite does not replace the signed integration test.

Release CI needs the actual Altillo Developer ID profile installed in addition to the existing P12
certificate import, target-specific provisioned settings and manual export mapping. Do not enable
automatic provisioning/account writes merely to run pull-request CI. OAuth client IDs and provider
approval remain independent prerequisites; a valid Apple profile does not make a mail provider
registration available.

The release workflow installs `ALTILLO_MAC_PROVISIONING_PROFILE_BASE64` from GitHub secrets and reads
the two public client IDs from repository variables `ALTILLO_GOOGLE_MAIL_CLIENT_ID` and
`ALTILLO_MICROSOFT_MAIL_CLIENT_ID`. It selects the profile only for the main application target.
The local profile is configured. The GitHub release secrets/public OAuth variables have not been
configured by this implementation; production Google/Microsoft client registration remains separate.

## Expanded account scope and validation

R61 now includes explicit send/reply, read/archive/trash actions, attachments, and iCloud/IMAP over TLS. This does not relax signing or Keychain requirements: server passwords/app passwords must use the same private, non-synchronizing vault. iCloud/IMAP do not require Google/Microsoft client IDs, but an ad-hoc build still cannot prove production credential access. The current distribution gate continues to require both OAuth registrations for the complete release.

Google authorization version 2 uses gmail.modify and gmail.send; Microsoft uses User.Read, Mail.ReadWrite and Mail.Send. Reauthorization, provider approval and real TLS/SMTP/IMAP checks are separate from signing. The previous 465 package + 921 macOS tests are a read-only baseline, not validation of these new operations. Consult [OAuth and server setup](mail-oauth.md) and [the plan](plans/mail-native-accounts.md) for the remaining acceptance checks.

Downloaded attachments saved to a user-selected path persist outside the in-memory mail cache. Sent messages, recipients' copies and provider-side drafts also persist under the provider's policies. Locking or deleting local credentials does not delete those files/messages. A valid signature does not prove send acceptance, final delivery, or safe handling of an uncertain send.
