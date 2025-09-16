# RMinder – Budgeting and Debt Reminder App

RMinder helps you plan your monthly budget, track spending, and stay on top of debts. It’s designed to be simple: set income, add category budgets, record transactions, and check reports. The app supports a digit-only currency input — just type 3-4-6-5 to get 34.65.

## Features

- Budget planning by category with monthly limits
- Track transactions with categories and notes
- Liabilities management (balance, minimum payment, extra payments)
- Monthly reports: allocation, spending by category, debt payment summary
- Digit-only currency input with auto-decimal formatting and 0.00 prefill

## Quick Start

1) Requirements
- Flutter 3.35+ and Dart 3.9+
- Android Studio or VS Code (recommended)

2) Install dependencies
- Open the project folder `rminder_app` in your IDE
- Fetch packages automatically or run:
	- flutter pub get

3) Run
- On Android emulator or device: run from IDE or:
	- flutter run

## How to Use RMinder

### 1. Set up Income
- Navigate to Budget tab.
- Tap Add under the Income section.
- Enter a name (e.g., Salary) and amount.
- Amount input is digit-only with auto decimal:
	- Typing 3465 becomes 34.65
	- Prefilled at 0.00; backspace reduces cents.

### 2. Create Budget Categories
- In the Budget tab, tap Add Budget.
- Enter a category name (e.g., Groceries, Rent).
- Set a Monthly Limit using the slider or the text field:
	- The text field shows two decimals (e.g., 91.37)
	- You can type digits only; decimal is automatic.
- Save to add the category.

Tips:
- The total of category limits is compared with your total income.
- The app shows warnings if you over-allocate above your income.

### 3. Record Transactions
- Go to the Transactions tab.
- Tap the + button (or Add action) to create a new transaction.
- Choose a Category, enter Amount and optionally a Note.
- Pick a date if needed.
- Save. The category’s "Spent" updates immediately.

Editing transactions:
- Tap a transaction to edit; save changes to update spending.

Filtering:
- Use the filter panel to narrow by category, date range/month, and amount range.

### 4. Manage Liabilities (Debts)
- Open the Liabilities tab.
- Tap Add Liability and fill:
	- Name, Current Balance, Minimum Payment
	- Each liability is automatically linked to a budget category for tracking.

Make payment:
- Tap the payment icon on a liability.
- Enter Amount to pay. If total paid this month exceeds the minimum, the excess is tracked as an extra payment.

Extra payment directly:
- If you’ve already met the minimum this month, the payment dialog switches to Extra Payment.

### 5. View Reports
- Go to Reports tab.
- Overview shows:
	- Total Income vs Total Budgeted
	- Unallocated Amount
	- Suggestion if over-allocated
- Spending by Category:
	- Shows spent vs limit, remaining, and category breakdown.
- Debt Payments:
	- Shows each liability’s minimum, paid, and over/under for the month.

### 6. End of Month (suggested workflow)
- In Reports, check leftover per category and total unspent across categories.
- Optionally carry over leftovers to next month as extra available amount.
- Reset categories as desired for the new month (adjust limits or leave as is).

## Tips & Conventions

- Amount fields are always digit-only with automatic 2-decimal formatting and start at 0.00.
- Budget limit sliders and labels show cents (two decimals) to avoid rounding surprises.
- Category and note fields have reasonable length limits (shown inline when reached).

## Building Release Artifacts (optional)

Android APK:
- flutter build apk --release

Android App Bundle:
- flutter build appbundle --release

Windows (if enabled in Flutter):
- flutter build windows --release

## Troubleshooting

- If analyze shows Radio deprecations, it’s safe; we’ll migrate to the newer RadioGroup API in a later update.
- If you see database issues, try uninstalling the app to clear local data (this resets your data).
- If slider feels too granular, you can type directly into the Monthly Limit field.

## License

MIT

