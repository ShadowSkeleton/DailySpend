# Platform and Toolchain Compatibility

The planned development environment is Xcode on macOS 27, with iOS/iPadOS 27 in scope. Treat that as required coverage, not permission to raise the minimum OS or assume every user has upgraded. Read actual build settings and supported installations.

## Evidence to capture

Record host `sw_vers`, selected Xcode developer directory, `xcodebuild -version`, Swift compiler build, SDK builds, simulator runtimes, supported device OS builds, minimum deployment targets, target architectures, app/extension entitlements, signing profiles, version/build, and candidate revision. Xcode MCP tools may supply these facts in an Xcode session; use the available tool rather than prescribing one environment.

Check current Apple documentation for the exact Xcode/macOS/iOS 27 minor releases and builds, whether stable or beta. Review SwiftData/Core Data, CloudKit, Foundation/Codable/date behavior, SQLite interaction, CryptoKit/Security/CommonCrypto, file providers, protected data, UserDefaults/App Groups, and WidgetKit changes relevant to this candidate. Do not turn a release-note keyword into proof of an app defect. Record known issues, mitigations, and whether they were reproduced; recheck on every release.

## Matrix to select from actual support

- Oldest supported iOS/iPadOS with the candidate SDK/build, and a representative currently deployed OS.
- iOS/iPadOS 27, including the current stable patch or explicitly targeted beta when available.
- App-only upgrade on the same OS, OS-only upgrade with the old app, then both orders of app plus OS upgrade on isolated devices.
- Old app/old OS paired with candidate/iOS 27 for production-compatible sync.
- Backup created by old app/OS restored by the candidate/iOS 27, plus supported device transfer/backup restore.
- macOS 27 host building, testing, and archiving all relevant targets; compare a previous toolchain when a framework behavior changed. Host success is not iOS runtime evidence.
- Running an iOS app on Apple silicon Macs or native macOS persistence only if that distribution/runtime is actually supported; host macOS alone does not make DailySpend a macOS app.

Cover actual minimum and maximum supported paths. Record unavailable runtime/device combinations as not tested and assess whether they hold the gate. Never fabricate a 27 runtime test from source inspection or assume a beta issue is fixed in the public release.

## Compatibility pitfalls

Check API availability gates, changed compiler/concurrency isolation, enum decoding across versions, configuration defaults and inferred store URLs, signing/capability changes, data-protection timing, and app/extension skew. An SDK upgrade without model-file edits can still change persistence behavior.

Test the signed Release archive as well as local builds. Compare resolved archive entitlements and identifiers to released artifacts; source entitlements alone do not prove production access. Preserve the deployment target unless an intentional support-policy change was requested, and explain what happens to data on devices that can no longer upgrade.

Do not promise downgrade safety. Determine whether an older binary can open the migrated store and consume the new cloud/backup contracts. If unsupported, prevent destructive reopen or repeated migration and document a safe recovery/forward-fix path. Retain prior archives and original snapshots without implying an App Store binary rollback automatically reverses data changes.

## Current official references

- [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes).
- [iOS and iPadOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes).
- [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes).
- [Configuring Xcode agents](https://developer.apple.com/documentation/xcode/extending-and-customizing-agents).

Follow the current official links for newer minor versions; record the source and access date. If browsing or tools are unavailable, keep local analysis moving and mark the platform claim unverified.
