# Tester data and App Store rollout workflow

Use this before the first public release and every later TestFlight cycle. Testers
use DailySpend for real expenses; treat their records as production data.

## Where to tell testers

- For a message they can read in TestFlight, use **App Store Connect → Apps →
  DailySpend → TestFlight → Additional → Test Information → Beta App Description**.
  Apple says edits there appear in the TestFlight app, but this is not a general
  push announcement.
- **What to Test** and **Notify Testers** are for an available beta build. Do not
  upload a new build solely to send a launch announcement.
- Send time-sensitive launch and migration instructions through the existing
  tester email or chat channel. Testers who joined through a public TestFlight
  link are anonymous to the developer in App Store Connect. Repost the message
  wherever the public link was shared. A new-build notification can reach
  assigned testers, but it cannot serve as a custom announcement for an
  already-available build.

Apple references: [Test Information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/),
[Notify external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/),
[tester information](https://developer.apple.com/help/app-store-connect/reference/testflight/testflight-tester-information/).

### Beta App Description to paste before the first release

> DailySpend is a free spending tracker and bill-splitting app. If you use real
> expense data, create an encrypted backup in Settings → Data Management before
> installing a new TestFlight or App Store version. Save the backup outside the
> app and keep its passphrase. Do not delete DailySpend to change versions.
> TestFlight and App Store builds use the same private iCloud data when sync is
> enabled, so edits and deletions can appear on your other devices. DailySpend
> 1.0 has been approved for the App Store. Please stay on your current build
> until I test the public release and share the App Store link. Send feedback
> through TestFlight without including private financial information.

After the public-build transition, remove the sentences about version 1.0
approval and waiting for the App Store link. Keep the backup, sync, and
feedback guidance in the Beta App Description.

## Data rules

1. Before any TestFlight update or switch to the App Store build, make a fresh
   backup in **DailySpend → Settings → Data Management → Create Encrypted Backup**.
   Save the file outside the app, confirm it exists, and keep the passphrase
   separately. DailySpend cannot recover a lost passphrase. A CSV export is not
   a complete backup.
2. Record the expense count, current totals, category budgets, and recurring
   entries before the change. Check them again after installing and opening the
   new build. Keep the backup until the checks pass.
3. Install a new TestFlight or App Store version **over the existing app**. Do
   not delete DailySpend first. The current app and widget identifiers must
   remain unchanged. Avoid switching back to an older public build after a
   newer beta has changed local data. If two DailySpend icons appear afterward,
   do not assume they are separate installations or delete either one. Check
   **iPhone Settings → General → iPhone Storage** for one or two DailySpend app
   entries. If there are two entries, back up data from each installation and
   contact the developer before removing either app.
4. TestFlight and App Store builds use the same private production CloudKit
   container. Edits and deletions made in a beta can sync to the user's other
   devices. iCloud sync is not a backup history. Run destructive tests on a
   spare device with a separate iCloud account, not a tester's real records.
5. If data is missing or totals change unexpectedly, stop using that build and
   contact the developer before deleting the app or restoring a backup. Do not
   repeatedly merge or replace data while iCloud sync is active without a
   recovery plan.

Apple warns that data may not survive a beta-to-public switch and recommends
backing it up: [TestFlight terms](https://www.apple.com/legal/internet-services/itunes/testflight/).
TestFlight builds expire 90 days after upload; publishing the app does not
automatically move testers to the public build: [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## First App Store release

CloudKit schema check (2026-09-25): the owner showed `CD_Expense` and
`CD_CategoryBudget` under **Production** for
`iCloud.com.jackson.LoveLedger` and reported **0 pending schema differences**
in Development. No schema deployment is indicated for the current 1.0 model.
The container also has other record types that are not in DailySpend's current
SwiftData models; leave those production types alone. This schema check does
not replace the two-device sync test below.

Public-build check (2026-09-25): the owner added an expense in the public
version and saw it in the TestFlight version. This is a positive result. If
both were opened on the same phone, confirm whether iPhone Storage shows one
or two DailySpend installations; one entry can mean that the two icons open
the same app, so the observation alone would not verify iCloud sync. A new
change reaching a second device on the same iCloud account verifies the
cross-device path.

- [ ] Before release, send the short pre-release note below. Ask testers to
      back up now and wait for a second message before switching.
- [ ] Confirm the approved App Store build and the TestFlight build currently
      used by the owner. Do not switch from a newer beta to older app code
      without an upgrade and migration check.
- [ ] Release version 1.0 in App Store Connect and wait for the public listing.
- [ ] **Owner first:** back up the owner's real data, record counts and totals,
      install the public build over the TestFlight build without deleting the
      app, then verify expenses, budgets, recurring entries, widgets, and
      private iCloud sync on a physical device. Seeing existing data in the
      public build is encouraging but does not by itself prove that a new
      change syncs. If two icons appear, check whether iPhone Storage lists one
      or two installations before advising testers. If anything fails, pause
      tester migration and investigate.
- [ ] Only after the owner's data checks pass, send the App Store link with the
      post-verification note below. Ask one backed-up tester to switch first;
      verify their data before inviting everyone else.
- [ ] Do not expire the TestFlight build while people still depend on it. Plan
      their transition before its 90-day testing window ends.

### Pre-release email to testers

**Subject:** DailySpend 1.0 approved — please back up before switching versions

> Hi everyone,
>
> DailySpend 1.0 is now marked Ready for Distribution in App Store Connect.
> Thank you for helping test it.
>
> Your expense data matters. Please make an encrypted backup now in DailySpend
> under Settings → Data Management → Create Encrypted Backup. Save the file
> outside the app and keep its passphrase. Please continue using your current
> installation; do not delete DailySpend or switch versions yet.
>
> I will test the App Store build with my own existing data first. Once that
> check passes, I will send the App Store link and steps for switching without
> deleting the app.
>
> Future TestFlight builds will remain optional. If you keep testing with real
> data, please back up before every beta update. Beta changes and deletions can
> sync through iCloud. If you prefer the more stable public version, you can
> stay on it and still send feedback. Please contact me if you have questions
> about protecting your data or notice anything unexpected.
>
> If you know friends who joined through the public TestFlight link, please
> forward this message or remind them to back up and wait for my follow-up. I
> may not be able to contact public-link testers directly.
>
> Thanks again for testing DailySpend and for your cooperation!
>
> Best regards,  
> Jackson Feng  
> Developer, DailySpend  
> Support: jacksonfeng0130@yahoo.com

### Note after the owner's public-build check succeeds

> I have verified the public DailySpend build with my own existing data. Before
> switching, make a fresh encrypted backup and keep its passphrase. Open this
> App Store link: **[insert verified App Store link]**. Install the public version
> over your existing TestFlight app; do not delete DailySpend first. Check your
> expenses, totals, budgets, and recurring entries afterward. Keep the backup.
> If two DailySpend icons appear, do not delete either one; contact me so we
> can check whether they are separate installations.
> If the App Store does not offer an install or anything looks wrong, stop and
> contact me before restoring or deleting anything. You can keep testing future
> builds if you want, or stay on the public version and still send feedback.

## Future release cycle

1. Develop and test new changes with disposable data and a separate iCloud
   account for destructive cases. Preserve the public bundle ID and CloudKit
   container for the actual upgrade path.
2. Test an in-place upgrade from the current App Store version on a physical
   device, including existing data and sync. Test migrations before exposing
   real-data testers to the build.
3. Give real-data testers the build-specific **What to Test** notes and a backup
   reminder. Make beta participation optional. Do not ask them to exercise
   destructive restore or deletion scenarios with important records.
4. Monitor tester feedback. Submit the same tested build for App Store review.
   After it goes live, verify the public build on the owner's device before
   telling testers to switch.
5. Tell testers when the public build is ready and guide them through the
   backed-up, in-place switch. Do not rely on TestFlight expiry as a migration
   plan.

## Version 2.0 TestFlight cycle

2.0 keeps the same app ID, widget ID, App Group, iCloud container, and
database model as 1.0. A TestFlight build replaces the App Store app on that
iPhone, and going back means installing the App Store version over it. Apple
says only that the beta "will replace" the App Store app; it does not promise
that data carries over. So every tester backs up first, even though the
simulator over-install and roll-back checks in the 2.0 release report pass.

Who this covers:

- **App Store 1.0 users who join the 2.0 beta.** The beta replaces their App
  Store app. They should back up before tapping Install.
- **Existing TestFlight testers.** They update from the 1.0 beta in place.
- **Testers with two devices.** If one stays on 1.0 and the other runs 2.0,
  both read and write the same iCloud records. 2.0 adds no new kinds of
  records, so 1.0 can show everything 2.0 saves. Long scanned notes may show
  in full in 1.0's lists, because 1.0 doesn't shorten them to the first line.

Inside the app, the first launch of 2.0 shows a one-time tour. People who
used DailySpend before see a first page with their expense count and a
**Back Up Now** button that saves the same encrypted backup as Settings.
That reminder comes after the install, so the messages below still ask for
a backup before installing.

Before inviting testers:

- [ ] Paste the 2.0 Beta App Description below in **TestFlight → Test
      Information**.
- [ ] Paste **What to Test** from `docs/TESTFLIGHT_NOTES.md` on the uploaded
      build.
- [ ] Owner first: back up, note counts and totals, install the TestFlight
      build over the App Store app on a physical iPhone, and check them.
      Then reinstall the App Store version over it and check again.
- [ ] Send the tester message below to the existing email/chat group, and
      repost it wherever the public TestFlight link was shared.

### 2.0 Beta App Description

> DailySpend is a free spending tracker and bill-splitting app. Version 2.0
> adds receipt scanning, Quick Add in plain words, Siri and Control Center
> actions, and a new Insights summary, all on your device.
>
> Protect your data first: before installing any beta or switching back to
> the App Store version, open DailySpend → Settings → Data Management →
> Create Encrypted Backup. Save the file outside the app, for example in
> Files or iCloud Drive, and keep its passphrase separately. Never delete
> DailySpend to change versions; install the new version over it.
>
> The beta replaces the App Store version on this iPhone. To go back, install
> DailySpend from the App Store over the beta. Beta and App Store versions
> share your iCloud data, so changes on one device reach your others. Send
> feedback through TestFlight, and hide private details in screenshots.

> DailySpend 是一款免费的记账与分账 App。2.0 版新增收据扫描、一句话快速记账、
> Siri 和控制中心操作，以及全新的统计速览，全部在你的设备上完成。
>
> 请先保护好数据：安装任何测试版或切回 App Store 版本之前，请打开
> DailySpend →“设置”→“数据管理”→“创建加密备份”。把文件保存到 App 之外
> （例如“文件”App 或 iCloud 云盘），并另外记好密码。切换版本时请不要删除
> DailySpend，直接在原 App 上安装新版本即可。
>
> 测试版会替换这台 iPhone 上的 App Store 版本。如需切回，从 App Store 重新
> 安装 DailySpend 覆盖测试版即可。测试版和正式版共用你的 iCloud 数据，一台
> 设备上的改动会同步到其他设备。欢迎通过 TestFlight 反馈，截图时请遮挡个人信息。

### 2.0 tester message

**Subject:** DailySpend 2.0 beta: please back up before you install

> Hi everyone,
>
> DailySpend 2.0 is ready to test. It can scan receipts, split a bill from a
> receipt, add expenses from a sentence like "Lunch with Alex 25", work with
> Siri and Control Center, and show a quick summary of your month in
> Insights. A short tour shows each of these the first time you open it.
>
> **Before you install, please back up:**
>
> 1. Open DailySpend → Settings → Data Management → Create Encrypted Backup.
> 2. Choose a passphrase you'll remember (at least 12 characters) and save the
>    file to Files or iCloud Drive, outside DailySpend.
> 3. Check that the file is there, and note how many expenses you have.
>
> **Then:**
>
> - Install the beta from TestFlight **over** your current app. Don't delete
>   DailySpend first; deleting it removes the copy on this iPhone.
> - Open it and check that your expenses, budgets, and recurring entries look
>   right. The first screen also offers a backup; it's fine to make another.
> - If you use DailySpend on more than one device, they keep syncing through
>   iCloud, even if one stays on the App Store version.
>
> **To go back** to the App Store version, install DailySpend from the App
> Store over the beta. Your records stay. Please back up again before you do.
>
> If anything looks missing or wrong, stop using the beta and reply to me
> before deleting the app or restoring a backup. Thank you for testing!

> 大家好：
>
> DailySpend 2.0 测试版已经可以安装了。新版本可以扫描收据、用收据直接分账、
> 用一句话记账（例如“和 Alex 吃午饭 25”）、配合 Siri 和控制中心使用，并在
> “统计”页显示本月速览。第一次打开时会有简短的介绍带你看一遍。
>
> **安装之前，请先备份：**
>
> 1. 打开 DailySpend →“设置”→“数据管理”→“创建加密备份”。
> 2. 设置一个你记得住的密码（至少 12 个字符），把文件保存到“文件”App 或
>    iCloud 云盘，不要只留在 DailySpend 里。
> 3. 确认文件已保存，并记下当前的账单数量。
>
> **然后：**
>
> - 在 TestFlight 里直接安装，**覆盖**现有 App。请不要先删除 DailySpend，
>   删除会清掉这台 iPhone 上的数据。
> - 打开后确认账单、预算和定期支出都正常。第一页也提供备份，可以再备份一次。
> - 如果你在多台设备上使用 DailySpend，即使其中一台还是 App Store 版本，
>   它们也会继续通过 iCloud 同步。
>
> **如需切回** App Store 版本，从 App Store 安装 DailySpend 覆盖测试版即可，
> 记录会保留。切换前请再备份一次。
>
> 如果发现数据缺失或异常，请先停止使用测试版并联系我，不要删除 App 或恢复备份。
> 感谢参与测试！
