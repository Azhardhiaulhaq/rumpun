# UI/UX redesign implementation evidence

Status: implementation in progress, not a completed antislop delivery gate.
Baseline: `8df37ac67eb70abc14dfd588de83c799d8bdbd86`.

## Implemented

- Household Beranda with profile access, real pending-review count, separate currency totals, monthly spending, recording choices, and informational location content.
- Keuangan navigation for Ringkasan, Riwayat, Tinjau, and Akun & aset.
- Android Back handling from internal finance destinations to Ringkasan and then Beranda.
- Existing `/review` entry opens Keuangan's review destination.
- Separate account and history views, account-type headings, and explicit missing-valuation copy.
- Noto Sans titles and white/soft-neutral surface tokens.
- Explicit paying-account selection and preservation of typed amounts when selecting the first account.
- Review card transaction dates.
- Reduced-motion handling for the app-wide navigation marker.

## Design reasons

Forest retains the existing identity and anchors financial values.
White surfaces improve legibility; soft neutral backgrounds separate account lists without heavy borders.
Clay highlights the recording action instead of competing with every navigation control.
Pending reviews precede balances because they require a decision.
Currencies remain separate because the UI has no supported exchange-rate conversion.
Location is informational because tracking is not implemented.
Account-type headings make similar accounts easier to scan.
Noto Sans keeps Indonesian labels and dense values consistent across screens.

Design read: shared household mobile app for a couple, grounded forest-green identity and white surfaces, ENERGY 2 / RHYTHM 2 / MOTION 2.
The motion target is not yet fully implemented.
The existing light-only theme is preserved; no new theme toggle was introduced.

## Automated evidence

- `flutter analyze`: no issues found.
- `flutter test`: 97 tests passed, without hit-test warnings in the final recorded run.
- `flutter build apk --release --dart-define-from-file=.env`: succeeded.
- `git diff --check`: passed.
- Contrast checker: white on forest is 9.84:1; white on clay is 5.80:1.
- Added household navigation, attention-link, coming-soon, and recording-choice tests.
- Updated existing navigation tests and golden references for changed typography and surfaces.
- Successful writes, confirmation, rejection, validation, and idempotency remain covered by fake-backend tests, not production phone writes.

Logs and private screenshots are in `/tmp/rumpun-redesign/`.
They contain real financial information and were intentionally not committed.

## Samsung evidence

Device rediscovered through ADB: Samsung Galaxy S23 FE, model `SM_S711B`.
The release APK was installed with `adb install -r`; no app-data clearing was performed.
The last source build was installed successfully and relaunched.

| Control or flow | Observed result | Evidence |
|---|---|---|
| Launch | Existing session restored into household Beranda | `latest-home.png` |
| Needs-attention action | Opened Keuangan Tinjau with actual proposals | `review.png` |
| Review description | Opened proposal details; no confirmation performed | `review-detail.png` |
| Riwayat | Opened posted history | `history.png` |
| Akun & aset | Opened account view | `accounts.png` |
| Android Back | Returned from accounts to overview, then Beranda | `home-bottom.png` |
| Catat uang | Opened expense, income, and transfer choices | `record-choice.png` |
| Pengeluaran | Opened amount form with keyboard | `expense-keyboard.png` |
| Keyboard dismissal and scrolling | Account selection and submission remained reachable | `expense-fields.png` |
| Empty expense submission | Invoked local validation only; no valid write payload entered | `expense-validation.png` |
| Location content | Displayed Lokasi keluarga and Segera hadir without a tracking control | `home-bottom.png` |

A sampled runtime-log scan after the initial release interactions found no Flutter exception or overflow matches.
The final runtime-log capture timed out, so it is not evidence of a clean final runtime session.

## Remaining before full delivery

- Remove the old finance overview action wall and duplicate profile header while retaining entry points and test coverage.
- Consolidate regular expense/income/transfer selection without losing opening balance, refund, and correction workflows.
- Complete purposeful navigation and expansion motion with reduced-motion coverage.
- Verify chart period coverage, misleading percentage comparisons, and labels against actual backend data.
- Finish remaining screen-specific redesign and branch-logo refinement.
- Preserve expected input state and scroll position across internal destinations; current internal destination switching remounts screens.
- Refresh household and finance attention counts after mutations and when returning to a retained screen.
- Complete phone click-through for income, transfers, valuations, profile, members, Gmail, OAuth returns, and notification entry points.
- Complete large-text, narrow-layout, keyboard, state, contrast, and accessibility checks for every changed screen.
- Run the full antislop delivery gate with control-by-control evidence before calling the entire plan complete.

No production transaction was posted, rejected, transferred, revalued, or edited for this testing.
No location permission or tracking implementation was added.
No backend deployment, credentials, household name, or hosting configuration was changed.
