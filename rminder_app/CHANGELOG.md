# Changelog

## [1.4.0] - 2025-11-18

### Highlights
- Immutable historical reports via full snapshot archival on Close Period.
- Carry-forward income UX: editable/deletable card on Budget; shows only when present.
- Local notifications with Android 13+ runtime permission support and a quick “Enable notifications” action.

### Added
- Period archival now snapshots everything on close:
	- Spending by category
	- Liabilities (planned vs paid)
	- Sinking funds (monthly contribution vs contributed)
	- Existing budget and income snapshots preserved
- Reports for closed periods read exclusively from snapshots (planned, actual/extras, and spending), so past periods no longer change when editing the active period.
- Global Close Period action available from any page.
- Budget page: Carry-forward income is a first-class, one-time card you can edit or delete. The card appears only when non-zero.
- Reports header polish: centered label between arrows; Jump button on the far right.
- Notifications:
	- Local notifications for budget alerts (over/near budget) and daily “record spending” reminder.
	- Android 13+ runtime permission flow; a simple “Enable notifications” menu item in Reports opens settings if denied.

### Changed
- Removed “Unspent amount” row and the “Includes carry-forward…” note in Reports’ Budget Summary.
- Restored Reports layout to previous UI (full-width summary, consistent section headings, overflow menu).

### Fixed
- Prevent closing a period on the active period’s start day to avoid invalid close ranges.
- Guarded async setState calls in Budget to avoid “setState() called after dispose()” crashes when navigating quickly.
- Android build fixes:
	- Enabled core library desugaring and upgraded flutter_local_notifications plugin.
	- Added POST_NOTIFICATIONS to AndroidManifest and permission request handling.

### Internal
- Database version bumped to v11 with new tables:
	- spending_snapshots(period_start, category_id, category_name, spent)
	- liability_snapshots(period_start, liability_id, liability_name, category_id, planned, paid)
	- fund_snapshots(period_start, fund_id, fund_name, category_id, monthly_contribution, contributed)

## [1.3.4] - 2025-11-18

### Fixed
- **Unallocated budget calculation**: Completely rewrote the budget calculation logic to follow the correct formula:
  - Budget = category budgets (excluding debt/fund categories) + planned debt payments + planned fund monthly contributions
  - Unallocated = income - budget - extra debt payments - extra fund contributions
- Debt payments now use liability's `planned` field instead of budget category limits
- Fund contributions now use sinking fund's `monthlyContribution` instead of budget category limits
- Extra contributions and debt payments are now subtracted from unallocated (not added to budget)

## [1.3.3] - 2025-11-18

### Fixed
- **Sinking fund extra contributions**: Extra contributions beyond the planned monthly amount now correctly reduce unallocated budget. Previously, only the planned monthly contribution was counted, so extra contributions didn't affect the unallocated amount.
- Unallocated calculation now uses sinking fund's `monthlyContribution` field instead of budget category's `budgetLimit` for accurate tracking.

## [1.3.2] - 2025-11-04

### Fixed
- Fund contributions calculation: withdrawals (spending from a sinking fund) no longer reduce the "contributed" amount for that period.
- Budget availability: fund withdrawals no longer create false "extra" budget availability in the active period.

## [1.3.1] - 2025-10-17

### Added
- Quick-edit budget snapshot for closed periods: adjust per-category limits without reopening.
- Quick-edit income snapshot for closed periods: adjust per-source income without reopening.

### Changed
- Budget page now considers extra loan payments and fund contributions when calculating the maximum available to allocate in the active period.
- Reports’ Unallocated now includes extras: amounts paid or contributed above planned limits reduce Unallocated.

### Fixed
- Edit period income dialog: “Add income source” now reliably adds a new row.

## [1.3.0] - 2025-10-17

### Fixed
- Active period persistence: prevent resets to earlier reset-day after closing; clamp active start to the day after the most recent closed period.
- Correct active period display fallback in Reports so it prefers the true active period over the last closed period during data load.
- Closed period end date: ensure the closed period ends on the intended close day and new period starts on the correct day.
- Edit period income: the “Add income source” button now correctly adds a new row in the dialog.

### Changed
- Carry-forward and debt-payment posting align to the end of the closing period for accurate historical reports.
- Unallocated calculation in Reports and charts now reflects “extras” beyond plan (extra debt payments and extra fund contributions), so intentional overpayments reduce Unallocated.

### Added
- Per-period income snapshots saved on close; closed period reports now use the exact income for that period (not today’s income settings).
- Quick-edit snapshots for closed periods (no reopen required):
	- Edit period income (per-source) via Reports → More → Edit period income.
	- Edit period budget limits per category via Reports → More → Edit period budget.
- Reports/Charts respect snapshots for closed periods; active period continues to use current budgets and incomes.

### Internal
- Database bumped to v10 with a new income_snapshots table (period_start, source_name, amount).
- One-time backfill of income snapshots for existing closed periods; reopen now removes both budget and income snapshots for that period.
- Database inference logic for active period hardened to avoid regressions across app restarts.

## [1.2.0] - 2025-10-01

## [1.2.1] - 2025-10-02

### Fixed
- Preserve current report period after update: initialize active period from the last closed period or reset-day inference, and correct bad "today" starts when earlier transactions exist.

### Added
- Global User guide: accessible from the AppBar menu; auto-shown once on first launch.
- Global Close period menu available on all screens.

### Changed
- Reports: Periods are user-driven; period range displayed between chevrons; jump-to-period picker.

### Fixed
- Overbudget false positive when income equals budget by switching comparisons to cents.
- Category names now stay in sync after renaming Sinking Funds or Liabilities (Transactions filter updates accordingly).
- Widget category list syncs after relevant edits.

## [1.1.0] - 2025-09-20

### Added
- Withdraw/spend from savings (sinking funds) with transaction record.
- Edit income sources and confirm before deleting income.
- Transactions page redesign: grouped by date, category icons, signed/color amounts, inline edit/delete, and note line.

### Improved
- UI polish and consistency in dialogs.
- Cleans up orphaned transactions if a category was removed.

### Fixed
- Analyzer: no new errors, only info-level lints remain.

---

See the release notes for details on new features and improvements.
