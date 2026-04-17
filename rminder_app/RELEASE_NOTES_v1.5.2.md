# RMinder v1.5.2 Release Notes

Release date: 2026-04-17

## Highlights

- Savings contribution totals are now consistent between Savings and Reports for the active period.
- Overview calculations now treat extra loan payments and extra fund contributions as planned outflow, reducing unplanned balance accordingly.
- Reports display is improved to avoid showing `-0.00` for near-zero values.

## Fixed

- Savings contributed amount now uses active-period transaction boundaries and counts only positive contribution transactions.
- Budget extra fund contribution logic now uses per-fund overage (`max(0, contributed - monthly)` per fund) instead of global netting.
- Budget and Reports overview cards now include extra debt payments above planned debt.
- Reports overview and savings deltas now normalize near-zero values to `0.00`.

## Changed

- Version updated to `1.5.2+14`.
- Overview cards in Budget and Reports continue to show: Planned, Unplanned, Spent, Remaining with aligned formulas.

## Included Files

- lib/providers/app_state.dart
- lib/screens/budget_screen.dart
- lib/screens/reports_screen.dart
- CHANGELOG.md
- pubspec.yaml
