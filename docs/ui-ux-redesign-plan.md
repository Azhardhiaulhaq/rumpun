# Rumpun UI/UX redesign plan

Status: agreed product direction, ready for implementation planning.
This document describes planned work, not features already implemented or tests already passed.

## Goal

Make Rumpun a shared household app for Azhar and his wife, with finance as one grouped feature area.
Modernise all existing screens while preserving their functionality and making room for location sharing and other household features later.
Use the current committed app as the implementation baseline.

## Agreed decisions

- Beranda becomes a shared household overview now.
- Finance lives inside Keuangan instead of occupying several app-wide tabs.
- Assets have their own view within Keuangan.
- Beranda includes clearly labelled coming-soon content for location sharing.
- Keep forest green and lightly refine the existing branch logo rather than replacing it.
- Use cleaner white surfaces, consistent sans-serif typography, fewer heavy borders, and clearer emphasis on amounts and actions.
- Add short, purposeful animations for navigation, expanding details, and review feedback.
- Use Indonesian throughout the interface, with readable dates and currency formatting.
- Redesign all existing screens, including authentication, finance forms, review, Gmail connection, and household settings.
- Test directly on the Samsung without changing real financial records merely to exercise controls.

Apply antislop during planning and implementation, with an evidence-backed delivery report at the end.

## Information architecture

### App-wide navigation

Initially provide two working destinations: Beranda and Keuangan.
Keep household settings, members, integrations, and sign-out behind the profile avatar.
Do not add empty navigation destinations for future features.

When location sharing is implemented, it can become a separate app-wide destination.
Future household features should follow the same grouping principle rather than becoming unrelated finance tabs or an expanding wall of home buttons.
Do not build a generic module framework before there is a concrete need for one.

### Beranda

Order the content as follows:

1. Household header with profile access.
2. Needs-attention section for pending email reviews, omitted when there is nothing to review.
3. Financial snapshot with total assets and this month's spending, linking into Keuangan.
4. Catat uang quick action with expense, income, and transfer choices.
5. Compact location coming-soon card.

Make the needs-attention section the focal point when reviews exist.
Otherwise, make the financial snapshot the focal point.
Keep detailed charts, account lists, and budget management inside Keuangan.

The location card must say “Lokasi keluarga” and “Segera hadir” or equivalent clear Indonesian copy.
Explain that the feature is not yet available without promising a release date or specific tracking behaviour.
Do not show fabricated positions, maps, people, GPS statuses, notification previews, or working-looking tracking switches.
Use informational content rather than a dead button.
Do not invent additional coming-soon features that the user has not named.

### Keuangan

Provide internal destinations for:

- Ringkasan: financial totals, spending, trends, and access to categories and budgets.
- Riwayat: posted transaction history and available transaction details.
- Tinjau: email proposals, their details, edits, confirmation, and rejection.
- Akun & aset: accounts, holdings, balances, and valuations.

Keep review counts visible on Beranda and at the finance entry points so proposals do not become difficult to discover.
Use internal navigation that remains comfortable on a phone rather than adding every destination to the app-wide bar.
Preserve existing history capabilities and confirm backend support before promising new search or filter behaviour.

Notification entry points must open the relevant finance review or Gmail screen directly.
Android Back must return through the expected screen hierarchy rather than trapping users in a nested destination.

## Screen changes

### Financial overview and charts

Replace the home button wall with the agreed overview and finance grouping.
Give currency controls a clear relationship to the values and charts they affect.
Keep different currencies separate unless an explicit, supported valuation exists.
Do not treat an unvalued asset as worthless or silently invent an exchange rate.

Align chart headings, selected periods, labels, and displayed amounts.
Use readable Indonesian month and date labels instead of raw API date strings.
Distinguish missing data from a recorded zero before calculating changes.
Do not show a percentage drop when the comparison would be misleading or the baseline is unavailable.
Verify calculations and data coverage before deciding whether an apparent gap is a display bug.

### Review

Lead each proposal with the available transaction description, amount, and date.
Use merchant information only when the source actually provides it.
Keep the original email subject and source content available in details.
Use a clear fallback when extraction does not provide a useful description.

Clearly distinguish Jev recommendations from confirmed user selections.
Keep suggestions editable and never overwrite explicit user choices.
Preserve candidate completeness checks and confirmation validation.
Keep edits, confirmation, rejection, errors, and successful actions visible and understandable.
Do not introduce bulk confirmation or swipe-to-post shortcuts in this redesign.

### Recording money and transfers

Provide one clear choice among expense, income, and transfer rather than duplicate type controls.
Show the amount prominently, followed by the fields relevant to the selected transaction type.
Make source and destination account roles explicit for transfers.

Do not default to the first account merely because it appears first in a list.
Without a reliable existing preference, require an explicit paying-account selection.
Preserve valid account eligibility, currencies, category rules, dates, and submission validation.
Ensure the keyboard does not hide the active field, validation feedback, or the path to submission.

### Accounts and assets

Group accounts by meaningful account types instead of presenting one long undifferentiated list.
Keep currency and ownership visible where needed to distinguish similar accounts.
Keep valuation actions distinct from transaction recording.
Show physical quantities separately from monetary values and explain missing valuations honestly.
Preserve account creation, transaction history, asset details, and valuation workflows.

### Remaining screens

Apply the same visual language and states to login, onboarding, household setup, members, invitations, Gmail connection, and any existing email setup screens.
Preserve OAuth return handling, sync progress, connection failures, and notification navigation.
Do not rename the real household as part of the redesign without a user-selected name.

## Visual direction and reasons

Reading this as: a shared household mobile app for a couple, with grounded forest-green identity, clean white surfaces, and ENERGY 2 / RHYTHM 2 / MOTION 2.

| Decision | Purpose |
|---|---|
| Forest `#234B38` | Preserve Rumpun's identity and anchor primary actions. |
| White surfaces and strong ink | Improve readability and consistency between overview, lists, and forms. |
| Restrained clay accent | Direct attention to the principal recording action without colouring every control. |
| Consistent Noto Sans typography | Keep Indonesian labels and dense financial values readable without changing type styles between screens. |
| Light branch-logo refinement | Improve small-size clarity while retaining the shared-root identity. |
| Section-specific layouts | Distinguish actionable reviews, financial summaries, and informational future content. |
| Structural whitespace | Separate tasks and groups without surrounding every row with a heavy border. |
| Relevant functional icons | Help users recognise navigation and account types without decorative AI symbols. |
| Selective elevation and rounded corners | Distinguish sheets and controls without making every element float or resemble a pill. |

Keep the branch motif restrained and recognisable rather than decorating every card.
Refine proportions, stroke clarity, and alignment using the existing geometry.
Keep in-app branding, launcher artwork, and notification assets consistent if the refinement changes them.
Use initials for avatars unless users provide profile imagery.

The agreed direction supersedes the paper-first surfaces, major serif titles, and MOTION 1 in the current `DESIGN.md`.
Update that file during implementation so future changes follow the agreed direction.
Do not silently introduce a new theme policy; decide any additional dark-mode scope before building and verify every theme that ships.

## Motion

- Use short navigation transitions to communicate movement between overview and detail.
- Animate expanding details so users can follow the content change.
- Use review feedback only after the server confirms the action.
- Keep loading feedback tied to actual work rather than decorative delays.
- Respect reduced-motion settings and avoid animation that blocks interaction.

Do not use looping decoration, bouncing controls, parallax, or reveal animations on every list item.
Preserve scroll position and input state where users expect to return to their work.

## Implementation sequence

1. Record the baseline commit, inspect existing tests and screen flows, and capture Samsung screenshots.
2. Reconcile `DESIGN.md` with this plan and establish shared colour, typography, spacing, and motion tokens.
3. Restructure the app shell and Keuangan navigation while preserving deep links and existing routes.
4. Build the household Beranda, review entry points, snapshot, quick action, and location placeholder.
5. Redesign finance overview, charts, review cards, detail screens, and recording forms.
6. Group accounts and assets, then bring remaining screens into the same design system.
7. Refine branding and check its appearance at launcher, notification, and in-app sizes.
8. Run automated checks and safe end-to-end flows, then inspect the release build on the Samsung.
9. Fix visual, accessibility, lint, test, and runtime issues and record delivery evidence.

Refactor reusable presentation components where needed instead of duplicating styling across the large existing screen files.
Keep the work focused on presentation and navigation unless a verified correctness issue requires a supporting fix.

## Validation and acceptance

### Automated checks

- Run Flutter formatting, analysis, and the existing test suite.
- Add coverage for the new shell, navigation, attention counts, coming-soon content, and form choices.
- Test loading, empty, error, and populated states.
- Test chart period labels, missing comparison data, and currency separation.
- Test reduced motion, larger text, and narrow layouts.
- Run relevant backend tests if implementation changes backend behaviour.

### Samsung checks

Use the currently connected Samsung Galaxy S23 FE and rediscover its ADB identifier rather than assuming a persistent Wi-Fi port.

Record screenshots and outcomes for:

- App launch and any safely testable authentication or restoration flows.
- Beranda and Keuangan navigation, internal finance views, and Android Back.
- Needs-attention links and notification-to-review navigation.
- Review card details, suggestion editing, and validation without confirming uncertain real transactions.
- Expense, income, and transfer forms, including keyboard and validation behaviour.
- Account groups, holdings, history, and valuation entry points.
- Profile, household members, invitations, and Gmail screens without triggering unnecessary real changes.
- Readable dates, amounts, currency controls, chart labels, and coming-soon content.
- Safe areas, scrolling, large text, touch targets, focus, and accessibility labels.
- Refined logo and launcher/notification appearance if those assets change.

Use test fixtures or an isolated test household for successful financial writes, rejection, invitations, and other mutating flows.
Do not post, reject, transfer, revalue, or edit production financial records solely for testing.
Do not claim a mutating flow passed on the real phone if it was only inspected or tested with fixtures.

Meet WCAG AA contrast and provide phone-friendly touch targets of at least 48 logical pixels.
Verify all shipped data screens have useful loading, empty, and recoverable error states.
Inspect runtime logs and resolve layout overflows and errors.

### Delivery evidence

Produce an antislop delivery report with written design reasons, screenshots, automated check results, and a control-by-control click-through record.
Distinguish phone evidence, automated fixture coverage, code inspection, and anything not exercised.
This plan is not that delivery report and does not assert that the redesigned app has passed validation.

## Deferred work

Actual GPS tracking, background location, arrival or departure detection, location notification rules, consent, privacy, battery impact, and retention need a separate design discussion.
The redesign must not request location permissions, collect positions, or enable tracking.
Additional household features and their coming-soon cards require explicit product decisions.
Production deployment, backend hosting, real ledger data, OAuth credentials, and household naming remain unchanged unless separately authorised.
