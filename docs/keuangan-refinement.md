# Keuangan overview refinement

Scope: Keuangan shell and Ringkasan presentation.
The wider redesign remains in progress.

Design read: focused household finance overview with sage balances, slate values, restrained apricot recording action, white navigation, ENERGY 2 / RHYTHM 2 / MOTION 2 inherited from the shared system.

## Changes and reasons

Removed personal and household greeting blocks so financial information leads immediately.
Replaced the dark asset carousel with one sage card showing separate currency totals, because multiple currencies must not be summed without conversion.
Slate amounts distinguish the primary values without covering the screen in forest green.
Apricot marks recording as the main action; transfer is a secondary text action.
Removed the account/history button wall because those views already have internal destinations.
Retained category and budget access, charts, currency selection, visibility, and recording workflows.
Rectangular rounded internal tabs distinguish navigation from action buttons.
Existing functional Material wallet, visibility, category, and transfer icons identify real controls rather than decorate unrelated content.

## Evidence

- Analysis: no issues.
- Tests: 98 passed in a normal run after golden updates.
- Release APK built and installed on Samsung Galaxy S23 FE through USB without clearing data.
- Phone screenshot: `/tmp/rumpun-redesign/finance-final.png`.
- Recording choice screenshot: `/tmp/rumpun-redesign/finance-choice.png`.
- Transfer entry screenshot: `/tmp/rumpun-redesign/finance-transfer.png`.
- No production financial writes performed.
- Diff whitespace check passed.
- Existing computed slate and sage/white contrast pairs retained.
- Fixed legacy Ringkasan label contrast revealed by the accessibility test.
- Added assertions that Ringkasan contains Total aset, has no greeting, and has no legacy account/history button.

## Control evidence

Keuangan bottom navigation opened the new Ringkasan on the phone.
Visibility toggled amounts on the phone.
Catat uang opened the recording choices on the phone.
Pindah dana opened the transfer entry on the phone, without submission.
Currency controls and chart gestures remain covered by the passing interaction tests.
Riwayat, Tinjau, and Akun & aset destinations remain covered by the shell navigation tests.
Category and budget entry remains the existing real route and was preserved by source inspection.

## Antislop gate for this scope

Hard gate PASS: real balances with separate currencies, no invented assets or names, real controls and existing data states, successful build and recorded phone checks.
Purpose gate PASS: sage/slate/apricot hierarchy, relevant icons, content-driven layout, and no ornamental gradients, glows, or illustrations.
Liveliness PASS: balance focal point, action and chart sections with different compositions, restrained accent, retained branch identity in the app, and purposeful shared navigation/sheet transitions.
Quality locks PASS: readable type, specific Indonesian actions, restrained corners, unchanged light-only policy, and all tests passing.

Existing backend-provided chart comparison percentages were not recalculated in this presentation change.
The previously documented chart data-coverage investigation remains separate outstanding work.
