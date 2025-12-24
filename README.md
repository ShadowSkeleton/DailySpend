DailySpend (LoveLedger)

DailySpend is a sleek, modern, and privacy-focused personal finance manager for iOS. Built entirely with SwiftUI and SwiftData, it offers a seamless experience for tracking expenses, managing budgets, and visualizing spending habits with native performance and iCloud synchronization.

✨ Features

Quick Logging: Add expenses in seconds with a clean, intuitive interface.

OCR Receipt Scanning: Use your camera to automatically detect and input total amounts from receipts.

Smart Budgeting: Set a global monthly budget and optional category-specific limits to keep your spending in check.

Recurring Transactions: Support for daily, weekly, monthly, and yearly recurring expenses.

Detailed Insights:

Trends: Visual line charts for spending patterns over time.

Breakdown: Interactive pie charts showing spending by category.

Activity: A specialized calendar view to track daily financial history.

Data Privacy & Sync:

Automatic iCloud Sync via SwiftData/CloudKit.

JSON Backup & Restore: Full control over your data.

CSV Export: Export your transaction history for external analysis.

Native Experience:

iOS Widgets: Monitor your monthly budget and 7-day trends directly from your home screen.

Daily Reports: Configurable notifications for budget status.

Dark Mode Support: Fully adaptive UI for light and dark environments.

Localization: Full support for English and Chinese.

🛠 Tech Stack

UI Framework: SwiftUI

Database: SwiftData (with CloudKit for sync)

Charts: Swift Charts

Persistence: AppStorage for settings

Scanning: Vision / VisionKit for OCR receipt recognition

Notifications: UserNotifications framework

🚀 Getting Started

Prerequisites

Mac running macOS 14.0 or later

Xcode 15.0 or later

iOS 17.0+ device or simulator

Installation

Clone the repository:

git clone [https://github.com/yourusername/DailySpend.git](https://github.com/yourusername/DailySpend.git)


Open LoveLedger.xcodeproj in Xcode.

Ensure your Development Team is selected in the Signing & Capabilities tab.

If you wish to use iCloud sync, ensure the iCloud capability is enabled and pointing to your container.

Build and run on your device or simulator.

📂 Project Structure

Expense.swift: The core SwiftData model for transactions and categories.

HomeViews.swift: The main dashboard featuring budget progress and recent activity.

InsightsViews.swift: Advanced analytics, charts, and calendar views.

TransactionViews.swift: Interfaces for adding, editing, and scanning transactions.

SettingsView.swift: Data management, budget configuration, and iCloud status.

AppUtils.swift: Localization engine (L10n), Notification management, and Widget services.

🔒 Privacy

DailySpend is designed with privacy as a priority. Your financial data is stored directly on your device and within your private iCloud container. No third-party servers are used for data tracking or analytics.

📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

Created with ❤️ by Jackson
