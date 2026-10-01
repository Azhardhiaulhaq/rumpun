# Ledger screen delivery gate

Design Read: household ledger for family members, in Rumpun's warm paper-and-forest visual language, ENERGY 2 / RHYTHM 2 / MOTION 1.
The focal point is the exact account value, with forest as the anchor and clay reserved for a valuation action.
The branch line on the home balance card remains the identity motif; the new ledger uses the same Noto Serif headings and Noto Sans financial detail.

## Hard gate

- R-02 PASS: no em dash appears in the new screen or form copy.
- R-03 PASS: 320-pixel widget tests cover long account names, a 12-character value code, large amounts, the ledger, and the account sheet without render overflow.
- R-17 PASS: account balances, valuations, and transaction amounts come from API responses, not invented figures.
- R-18 PASS: no testimonials or synthetic people appear in these screens.
- R-23 PASS: no new logo, avatar, photograph, statistic, or bottom-navigation structure was created; the ledger is reached through a labeled home action.
- R-24 PASS: the new home action opens the ledger and the back button returns home.
- R-25 PASS: measured forest on white at 9.84:1, muted ink on paper at 6.33:1, deep clay on white at 7.58:1, and ink on paper at 13.89:1; the input border on cream is 3.80:1 for a non-text boundary.
- R-26 PASS: account creation, asset valuation, transaction detail and reversal, pagination, date selection, and retry actions have wired handlers and tested outcomes.
- R-27 PASS: the ledger has explicit loading, error with retry, and empty-account and empty-history states; valuation history has loading, error, and empty states.
- R-28 PASS: no FAQ was added.
- R-32 PASS: controls use Flutter buttons, fields, dropdowns, and dialogs with keyboard focus and Escape/back dismissal; the existing keyboard accessibility suite passes.
- R-33 PASS: UI features were edited in Dart source with patches and compiled by Flutter.
- R-34 PASS: no theme toggle was added; the app retains its existing light theme.
- R-35 PASS: built and ran on Samsung SM S711B; tapped home to ledger, opened the account sheet, checked its keyboard and no-keyboard layouts, dismissed it, and returned home; widget tests cover account save, valuation save, opening balance and date picker, cross-currency transfer, reversal, and history pagination.
- R-36 PASS: no security, compliance, customer, or performance claims were added.
- R-37 PASS: the declared design direction comes from `DESIGN.md` and was applied during screen work.
- R-38 PASS: empty states are honest and the screen uses actual household API data.

## Purpose gate

- R-01 PASS: no new gradient or glow was added; forest highlights the household's primary actions.
- R-04 PASS: wallet, bank, currency exchange, calendar, ledger, and asset icons identify their corresponding actions and account forms.
- R-06 PASS: Noto Serif headings evoke the existing personal ledger identity and Noto Sans keeps amounts and controls legible.
- R-07 PASS: no stock grid or background pattern was added.
- R-08 PASS: no decorative arrows were added to the new actions.
- R-09 PASS: no decorative badges were added.
- R-10 PASS: no glass surface was added.
- R-12 PASS: new account and transaction cards stay flat; they have no arbitrary shadow.
- R-13 PASS: no glow was added.
- R-14 PASS: accounts and transactions use different compositions because account value and event history answer different questions.
- R-19 PASS: no looping or decorative animation was added, consistent with MOTION 1.
- R-22 PASS: no unrelated illustration was added.

## Liveliness

- Dials PASS: ENERGY 2 / RHYTHM 2 / MOTION 1 are stated above and come from `DESIGN.md`.
- Consistency PASS: restrained flat cards, a warm ground, and minimal motion hold across home, ledger, and sheets.
- Focal point PASS: the account value leads each holding; the transaction amount remains exact and legible in history.
- Whitespace PASS: spacing separates account holdings from transaction history and gives each form field room for validation text.
- Accent PASS: clay marks the valuation action and errors, while forest carries primary actions.
- Identity PASS: the existing branch motif, forest palette, and serif/sans pairing remain consistent.
- Design Read PASS: the design direction was declared before the screen edits.

## Craftsmanship and quality locks

- C-1 PASS: the ledger follows the household's existing materials and palette, not a default dashboard template.
- C-2 PASS: all added controls have behavior, including save, retry, pagination, date selection, back, and reversal.
- C-3 PASS: accounts, values, and history are present because they are the requested tracking workflow.
- C-4 PASS: tests cover loading, empty, error, 320-pixel width, long values, and keyboard-safe bottom sheets.
- C-5 PASS: no unverified figures or claims were added.
- R-05 PASS: the page moves from holdings to event history, not a uniform grid of generic cards.
- R-11 PASS: form fields, account cards, transaction entries, and primary buttons use distinct purposeful radii.
- R-15 PASS: actions say what they do: add account or asset, record value, show older history, and reverse transaction.
- R-16 PASS: new Indonesian copy avoids marketing buzzwords.
- R-20 PASS: the Rumpun branch, warm ledger ground, and family-finance language make the UI product-specific.
- R-21 PASS: the existing warm light theme is retained as specified by the brand.
- R-29 PASS: paper, forest, and ink form the core palette, with clay as a limited accent.
- R-30 PASS: the screen extends the existing product instead of copying another app's layout.
- R-31 PASS: the account list puts value beside its named holding; history gives exact event detail and keeps original entries after reversal.

## UI, human, and mobile supplements

- UI PASS: the empty states name the missing record and its next action, and no dead navigation or decorative status dot was added.
- Human PASS: text and component-boundary contrast were computed, form errors use words, and native controls keep visible focus and keyboard operation.
- Mobile PASS: the 320-pixel test exposed and resolved two dropdown overflows; the final test covers account and history amounts without horizontal clipping, and bottom sheets scroll above the keyboard.
- Verification PASS: `flutter analyze`, 82 Flutter tests, 92 backend tests, Ruff, mypy, PostgreSQL migration SQL compilation, and the live ngrok smoke test passed.

The live port-8001 backend now uses `.local/rumpun-live.db`, a persistent git-ignored copy of the household created during phone testing.
The production PostgreSQL migration compiled successfully but has not been applied to a running PostgreSQL instance.
An Alembic upgrade from an empty SQLite database remains unsupported by an earlier migration that tries to drop a SQLite column default; the local live database uses the current schema directly.
