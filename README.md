
# 📱 DailySpend

**Smart bill splitting. Private spending. Effortless tracking.**
A premium iOS expense manager and **Smart Split Bill** assistant built with **SwiftUI** and **SwiftData**.

DailySpend is a sleek, privacy-focused personal finance manager for iOS. Its signature **Smart Split Bill** experience makes group meals, trips, and shared purchases easy to settle fairly, then lets you save your share alongside your everyday spending. Track expenses, manage budgets, and understand your financial health with full **iCloud synchronization** across your devices.

---

## ✨ Core Features

| Feature | Description |
|------|------------|
| 🤝 **Smart Split Bill** | DailySpend’s signature feature: split a total evenly or item by item, share items among the right people, and settle every cent accurately. |
| ⚡️ **Quick Log** | Record expenses in seconds with a highly optimized input flow. |
| 🔍 **OCR Scanner** | Scan receipts using the camera to automatically detect total amounts. |
| 📊 **Smart Budgeting** | Set global monthly targets or specific category-level limits. |
| 🔁 **Recurring** | Support for Daily, Weekly, Monthly, and Yearly automated entries. |
| 📈 **Rich Insights** | Visual trends, category breakdowns, and a detailed activity calendar. |
| ☁️ **iCloud Sync** | Your data stays in sync via CloudKit without third-party servers. |
| 📦 **Data Portability** | Password-encrypted JSON backup/restore and CSV export for external analysis. |

---

## 🤝 Smart Split Bill — the DailySpend difference

Most expense trackers stop at logging a purchase. DailySpend helps you settle it first.

- **Choose the right split:** divide a total evenly in seconds, or itemize a receipt and assign each item to the people who shared it.
- **Handle the real bill:** add tax and a percentage or fixed tip; DailySpend calculates each person’s fair total.
- **No lost pennies:** cent-accurate allocation ensures every share reconciles exactly with the original bill.
- **Make the result useful:** review a clear per-person breakdown, share the finished receipt, and save the relevant share as an expense.

---

## 🛠 Tech Stack

- **UI Architecture:** SwiftUI (Declarative UI)  
- **Data Engine:** SwiftData (with CloudKit integration)  
- **Visualizations:** Swift Charts  
- **Scanning Engine:** VisionKit & Vision (OCR)  
- **Notifications:** UserNotifications  
- **Widgets:** WidgetKit  

---

## 🚀 Getting Started

### Prerequisites
- **macOS:** 14.0 (Sonoma) or later  
- **Xcode:** 15.0 or later  
- **Device:** iOS 17.0+ (Required for SwiftData)  

---

### Installation

#### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/DailySpend.git
````

#### 2. Open Project

Open `DailySpend.xcodeproj` in Xcode.

#### 3. Configure Signing

Select your **Development Team** in the **Signing & Capabilities** tab.

#### 4. iCloud Setup

For a signed distributed build, enable the **iCloud** capability and ensure the private CloudKit container is correctly assigned.

#### 5. Run

Select your device or simulator and press **Cmd + R**.

---

## 📂 Project Navigation

* `Expense.swift` — Core data schemas
* `HomeViews.swift` — Main dashboard and budget tracking
* `InsightsViews.swift` — Analytical charts and calendar logic
* `TransactionViews.swift` — Add/Edit flows and OCR scanning logic
* `SettingsView.swift` — Configuration, iCloud status, and backup tools
* `AppUtils.swift` — Localization engine (L10n) and helper services

---

## 🔒 Privacy First

DailySpend is designed with **zero-tracking** in mind.

* **Local-First:** Data lives on your device
* **Apple-Secure:** Syncing uses your private iCloud storage
* **No Third Parties:** No external analytics or trackers included
* **Encrypted Backups:** New JSON backups use a passphrase that DailySpend never stores

The in-app policy is also mirrored in [`docs/privacy/index.html`](docs/privacy/index.html) for App Store hosting.

Created with ❤️ by **Jackson Feng**
