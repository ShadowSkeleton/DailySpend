# DailySpend App Store release checklist

Use this for the signed distribution build. It does not replace a real-device
TestFlight pass.

## Protect current testers before updating

- Ask testers to keep a current backup or CSV export and to confirm iCloud
  sync is healthy before installing the release candidate.
- The money update is additive: it only fills a new optional cents field and
  leaves every existing stored `Double` amount unchanged. If the backfill is
  interrupted, DailySpend continues reading the original amount.
- Test an upgrade over an existing TestFlight build on a real device. Confirm
  past expenses, category budgets, recurring templates, and split receipts
  are still present.

## Required real-device tests

- Sign in to iCloud, create an expense on one device, and verify it arrives on
  a second device using the private CloudKit database.
- Test receipt scanning after accepting the camera permission.
- Turn on App Lock, background the app, return to it, and verify both the
  app-switcher shield and device-authentication flow.
- Create an encrypted backup, restore it with the right passphrase, and make
  sure a wrong passphrase does not import anything.
- Exercise replacement restore: save the required safety backup, then cancel
  and complete the final confirmation separately.

## Apple signing and services

- Archive with the distribution signing profile for `com.jackson.LoveLedger`.
- Confirm the archive’s entitlements use the production APS environment and
  include `iCloud.com.jackson.LoveLedger` plus
  `group.com.jackson.LoveLedger`. Let Xcode and the distribution provisioning
  profile provide the production APS value; do not hand-edit it for release.
- In CloudKit Dashboard, deploy the tested development schema to Production
  before the App Store build can create production records.

## App Store Connect metadata

- App name: `DailySpend: Smart Split Bill` (keep `DailySpend` as the brand).
- Support email: `jacksonfeng0130@yahoo.com`.
- Publish the static policy in this repository using `docs/README.md`, then
  add the public HTTPS `/privacy/` URL to both App Store Connect and the app’s
  support materials.
- Complete App Privacy from the actual shipped build. With the current code,
  no data is sent to the developer, ads, analytics, or third parties; confirm
  this remains true before selecting “Data Not Collected.”
- Upload final iPhone screenshots and ensure they show DailySpend (not the
  project’s former LoveLedger name).

## Submission gate

- Build and test a Release archive, not only a simulator Debug build.
- Keep a copy of the exact archive and the matching privacy-policy version.
- Do not submit until the signed CloudKit, camera, backup/restore, and App
  Lock checks above have passed on a physical device.
