# DailySpend 2.0 — build, TestFlight, and App Store guide

Step by step for 2.0 (16), checked against Apple's App Store Connect help on
October 28, 2026 (links at the end). Labels in **bold** are what App Store
Connect and Xcode show. Copy for every field is in
[docs/marketing/V2_MARKETING.md](marketing/V2_MARKETING.md); tester text is in
[docs/TESTER_DATA_WORKFLOW.md](TESTER_DATA_WORKFLOW.md) and
[docs/TESTFLIGHT_NOTES.md](TESTFLIGHT_NOTES.md).

Before you start: back up your own DailySpend data (Settings → Data
Management → Create Encrypted Backup) and keep the passphrase.

## A. Build and upload

1. In Xcode 27.1, open `DailySpend.xcodeproj` on `main` (after the 2.0 PR is
   merged). Pull first so you build what was reviewed.
2. Select the **DailySpend** target → **General**: Version **2.0**, Build
   **16**. Each upload needs a higher build number than any earlier upload
   for this app, so a later fix becomes 17.
3. In the toolbar, choose the **DailySpend** scheme and **Any iOS Device
   (arm64)** as the destination.
4. **Product → Archive.** Archive uses the Release configuration. When it
   finishes, the **Organizer** opens on the new archive (2.0 (16)).
5. Click **Distribute App** → **App Store Connect** → **Distribute**. Keep
   automatic signing. Don't choose **TestFlight Internal Only**: that build
   can never go to external testers or the App Store.
6. Wait for the upload to finish, then for processing (often 15–60 minutes;
   Apple emails you). In App Store Connect → **TestFlight**, the build shows
   under **iOS Builds** → 2.0.
7. **Export compliance.** If the build shows **Missing Compliance**, click
   **Manage** and answer as you did for 1.0. 2.0 uses the same encryption
   (CryptoKit AES-GCM for backups, Apple's own APIs). If your 1.0 answer was
   that the app is exempt, you can later add `ITSAppUsesNonExemptEncryption
   = NO` to Info.plist so it stops asking; don't add it unless that was your
   answer.

## B. TestFlight

### Yourself first (internal)

1. **TestFlight → Internal Testing**: open your group (or create one with
   **+**) and add build 16. Internal testers need App Store Connect access;
   up to 100 people.
2. On your iPhone, open the **TestFlight** app and install DailySpend 2.0.
   It **replaces** the App Store version on that phone (same app).
3. Check: your expense count and totals match the backup you just made,
   the tour opens on "Your N expenses are all here", iCloud sync still
   works with your other devices.

### External testers

1. **TestFlight → Test Information** (left sidebar, **Additional
   Information**): paste the **2.0 Beta App Description** (English; add the
   Chinese one under Simplified Chinese if you localize test info), check the
   feedback email and privacy policy URL.
2. Open build 16 → **Test Details** → **What to Test**: paste the 2.0 text
   from `docs/TESTFLIGHT_NOTES.md`.
3. **External Testing** → your group (create one with **+** if needed;
   Apple requires an internal group to exist first) → **Builds** → **+** →
   build 16 → **Submit for Review**. The first build of a new version goes
   through TestFlight App Review, usually within a day. You can submit up to
   six builds in 24 hours.
4. When it's approved, testers get it by email invite or your **Public
   Link** (enable it in the group). Up to 10,000 external testers.
5. Send the **2.0 tester message** (email/chat) and repost it wherever the
   public link was shared. TestFlight can't send a custom announcement to
   public-link testers.
6. Watch **TestFlight → Feedback** (screenshots and crash reports from
   testers) and **Xcode → Window → Organizer → Crashes**. Each build can be
   tested for up to 90 days.
7. A fix: raise the build to 17, rerun the release checks
   (`dailyspend-quality` and `dailyspend-upgrade-safety`), upload, add it to
   the groups, update **What to Test**.

## C. Submit 2.0 to the App Store

### What changes when

| Can change any time, no review | Needs review, but not a new app version | Only with a new app version |
|---|---|---|
| Promotional text; pricing and availability | In-App Events; custom product pages; product page optimization tests; header and search results assets (approved in the Asset Library) | Description, keywords, What's New, screenshots and previews, support/marketing URLs, name and subtitle |

So: put everything from the marketing kit into the 2.0 version now. After
release, you can change the promotional text and run events or tests
without shipping a new build.

### 1. Create the version

**Apps → DailySpend → Distribution**, then **+** next to **iOS App** →
enter **2.0** → **Create**. The new version opens as
**Prepare for Submission**.

### 2. Product page text (each language)

Top right, the language menu shows **English (U.S.)**. Fill in, then switch
to **Chinese, Simplified** (add it in **App Information → Localizable
Information** if it isn't listed) and fill in the Chinese copy:

- **Promotional Text** (170): from the kit.
- **Description**: the new opening plus the feature blocks.
- **Keywords** (100, commas, no spaces).
- **Support URL**, **Marketing URL**: unchanged.
- **What's New in This Version**: the 2.0 bullets.

**App Information** (left sidebar, **General**): **Name** stays
`DailySpend - Spend & Split`; set **Subtitle** to
`Scan Receipts & Split Bills` (Chinese: `扫描收据，轻松记账分账`). These
change only with this submission.

### 3. Screenshots and previews

Under **App Previews and Screenshots** for each language:

- **iPhone**: the largest size App Store Connect asks for (6.9-inch;
  6.5-inch is also accepted). One to ten images, no transparency.
- **iPad**: 13-inch (DailySpend supports iPad).
- **iPhone Duo**: optional until April 2027, then required for apps built
  with the iOS 27.1 SDK or later. Uploading them adds the "optimized for
  iPhone Duo" badge; planned for 2.x.
- An **App Preview** video is optional (up to 30 seconds of screen
  recording).

Use the seven frames in the marketing kit (English and Chinese sets).

### 4. Header and search results (optional, iOS 27 and iPadOS 27)

On the version page, **Product Page Information → Header and Search
Results**:

- **Header**: 21:9, 3840 × 1646 image (.jpg/.png) or a 5–30 second video,
  shown above your product page.
- **Search Results**: 3:2, from 1920 × 1280 up to 3840 × 2560, shown in
  search on iOS 27.
- **Browse Assets** picks from the **Asset Library** (sidebar, **Growth &
  Marketing**), where you can upload and get assets approved ahead of time.
  **Preview** shows header, screenshots, and text together, including Dark
  Mode. They add to screenshots; they don't replace them.

### 5. Privacy and rating

- **App Privacy** (sidebar, **Trust & Safety**): confirm **Data Not
  Collected** is still true. 2.0 adds on-device Apple Intelligence and no
  analytics, ads, or servers, so the answers shouldn't change; click
  **Publish** only if you edit them.
- **Age Rating** (in **App Information**): review the answers; 2.0 adds no
  new content types.

### 6. Build and review information

- **Build**: click **Add Build** (or **+**) and choose **2.0 (16)**.
- **App Review Information**: contact details; **Sign-in required** off.
  Notes (example): "DailySpend has no account. Receipt scanning and Quick Add
  categories use on-device Apple Intelligence where available; other devices
  read receipt totals. A one-time tour shows the new features (Settings →
  What's New in DailySpend 2.0). Everything runs on device; iCloud sync is
  optional."
- **Version Release**: choose **Manually release this version**.
  Optional: **Phased Release for Automatic Updates** spreads automatic
  updates over seven days and can be paused for up to 30 days; people can
  still update by hand.

### 7. Submit

1. **Add for Review** (top right) → create a new submission. The version
   becomes **Ready for Review**; nothing is sent yet.
2. In the submission panel, check the items and click **Submit for
   Review**. Status: **Waiting for Review** → **In Review**.
3. If App Review asks something, answer in **App Review → Messages**.
4. After approval the status is **Pending Developer Release** (Apple emails
   a reminder after 30 days).

### 8. Release and after

1. Click **Release This Version**. It can take up to 24 hours to appear
   everywhere.
2. Install the App Store update on your own iPhone over your data and
   check counts, totals, iCloud sync, and widgets.
3. Then tell testers they can switch (the note in
   `docs/TESTER_DATA_WORKFLOW.md`).
4. Start the **In-App Event** (sidebar, **Growth & Marketing → In-App
   Events**, badge **Major Update**), post the launch messages, and update
   **Promotional Text** whenever you like.
5. Keep the 2.0 TestFlight build available until testers have moved; don't
   rely on its 90-day expiry.

## Sources

- [App Store Connect workflow](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow/)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
- [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- [Select an App Store version release option](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/)
- [Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/)
- [Overview of publishing your app](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store/)
- [Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/)
- [Manage your App Store assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [App Store Connect release notes](https://developer.apple.com/help/app-store-connect/release-notes/)
