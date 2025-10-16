# Changelog

## [1.3.0] - 2025-10-16

### Fixed
- Active period persistence: prevent resets to earlier reset-day after closing; clamp active start to the day after the most recent closed period.
- Correct active period display fallback in Reports so it prefers the true active period over the last closed period during data load.
- Closed period end date: ensure the closed period ends on the intended close day and new period starts on the correct day.

### Changed
- Carry-forward and debt-payment posting align to the end of the closing period for accurate historical reports.

### Internal
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
