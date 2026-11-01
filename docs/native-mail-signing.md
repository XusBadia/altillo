# Signing native mail account builds

Reviewed 1 November 2026. The native Google credential vault selects the macOS Data Protection
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

## Local state inspected

The installed official application has bundle ID `me.badia.altillo`, team `9L2TD7KVV9`, and Developer
ID signing. Its current signature has the existing four permissions and no application identifier.
No Altillo macOS profile, nor a suitable macOS wildcard profile, was present in either standard local
profile directory during this review.

The account already has an unrelated macOS Developer ID profile for another explicit App ID. That
establishes that Developer ID provisioning has been used with this account; that unrelated profile
does not authorize Altillo and must not be copied into it. Other discovered profiles were for iOS.
Only profile metadata was inspected; no private keys or credentials were read and no Apple account
registrations or profiles were created or changed.

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
6. Run a signed integration test that creates, reads and removes a synthetic record using a fresh
   isolated service name; never enumerate or delete a person's mail credentials for this test.
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
These external values have not been configured by this implementation.
