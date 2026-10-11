# Beranda refinement delivery

Scope: the revised three-card Beranda and lighter app-wide navigation, not completion of the original full-app redesign plan.

Design read: shared household mobile overview, clean white and muted sage surfaces with slate financial values and apricot recording accent, ENERGY 2 / RHYTHM 2 / MOTION 2.

## Design reasons

Sage distinguishes the shared household from financial information without a large dark-green block.
Slate gives financial values strong contrast and introduces a second visual anchor.
Apricot directs attention to recording without making the whole screen orange.
White navigation reduces visual weight at the bottom of every screen.
The existing branch logo retains Rumpun's identity; member initials represent actual server-provided people without invented imagery.
Home, invitation, wallet, visibility, review, and location icons communicate their adjacent labels or actions.
Member rows use horizontal composition, finance uses value hierarchy, and the compact location card uses icon and explanatory text.
Financial detail expansion uses a 220 ms size transition and rotating chevron to connect control and content.
Reduced motion renders details directly, avoiding the zero-duration AnimatedSize layout error reproduced in the large-text test.
No stock imagery, fabricated maps, or decorative looping animation was added.

## Verification

- Flutter analysis: no issues.
- Flutter tests: 98 passed.
- Release build: succeeded and installed on the USB-connected Samsung Galaxy S23 FE without clearing app data.
- Diff whitespace check: passed.
- Narrow 320 logical-pixel layout, 200% text, and reduced-motion expansion: fixture test passed.
- Existing keyboard activation, chart, review, ledger-write, and session tests: passed.
- Updated golden references for revised Beranda and white navigation.
- Slate on financial surface: 8.41:1.
- Deep clay on apricot: 6.47:1.
- Existing forest on white: 9.84:1.

## Phone control evidence

| Control | Result |
|---|---|
| Launch | Restored session and displayed real household name and member list |
| Undang anggota | Opened existing invitation form; dismissed without sending |
| Visibility | Hid asset and monthly-spending values |
| Rincian aset | Expanded details with explanatory currency copy and account link |
| Tutup rincian | Same toggle collapses details; covered by source inspection and fixture expansion assertions |
| Review shortcut | Opened review in fixture navigation coverage; underlying phone review flow was exercised in the preceding implementation |
| Catat uang | Three choices verified by fixture click-through; existing sheet behavior retained |
| Buka keuangan | Uses the existing shell destination callback; finance navigation fixture passes |
| Profile | Retains existing profile sheet callback and passing profile/Gmail golden flow |
| Location | Informational only, no fake tracking action |
| Pull to refresh | Reloads all four real data requests with recoverable failures |

Private phone screenshots: `/tmp/rumpun-redesign/clean-home2.png`, `clean-invite.png`, `clean-final-expanded.png`, and `clean-final-location.png`.
A sampled runtime-log scan produced no matching Flutter exception or overflow lines.
No production invitation or financial write was performed.
Only one household member was returned by the real API; no additional person was invented.

## Antislop delivery gate

- Hard gate PASS for this refinement: real API content, honest location placeholder, useful inline loading/error/empty handling, functioning controls, no added permissions or fabricated assets, successful build and recorded phone/fixture evidence.
- Purpose gate PASS: palette, icons, composition, and expansion motion have the written reasons above; no gradients, glow, glass, or stock illustrations.
- Liveliness PASS: three distinct compositions, financial focal point, structural spacing, restrained apricot accent, existing branch identity, and purposeful expansion motion.
- Craftsmanship and quality locks PASS for this refinement: three requested content groups, specific Indonesian actions, restrained radius hierarchy, existing light-only policy preserved, contrast computed, and all 98 tests passed.

The wider full-app redesign remains in progress as documented in `ui-ux-redesign-progress.md`.
