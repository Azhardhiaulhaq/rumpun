# Rumpun design direction

Identity: a shared household app that treats family life as something tended together, with finance as one grouped area.

Personality: grounded, reassuring, candid, and practical.
Never glossy or bank-corporate.

Palette:
- Forest `#234B38` for small identity anchors and selected navigation, not large filled surfaces.
- Sage `#EDF2ED` for the family card and slate `#354C60` for financial values.
- Apricot `#FFE9DB` with deep clay text for the recording action.
- Moss `#6F8265` for supporting information.
- Clay `#A44B2B` as the single attention accent, darkened to keep white action labels above WCAG AA.
- White `#FFFFFF`, soft neutral `#F5F7F5`, and ink `#20251F` for readable surfaces.
- Forest-tinted backgrounds separate supporting information without heavy borders.

Typography: Noto Sans throughout, with strong weight and size hierarchy to keep Indonesian labels and financial values readable.

Mood: clean white surfaces, strong ink, restrained botanical linework, and flat surfaces.

Identity motif: one continuous branch line that joins leaf-shaped nodes, representing people and financial accounts sharing one root.

Dial: ENERGY 2 / RHYTHM 2 / MOTION 2

Theme policy: preserve the existing light-only app for this redesign.
Additional dark-mode scope needs a separate product decision.

Motion: short navigation and expansion transitions explain hierarchy and state changes.
Respect the platform reduced-motion setting.

Layout: Beranda contains exactly three sections: household name and real members with invitation access, one financial summary card including review access and recording, then compact location coming-soon content.
Use compact member rows rather than large greetings or a separate review card.
Keuangan contains Ringkasan, Riwayat, Tinjau, and Akun & aset, keeping detailed finance tools out of the household overview.
The bottom navigation has four destinations: Beranda, Keuangan, Lokasi, and Daftar.
Daftar holds shared checklists and free-form notes; apricot marks its create and add actions, matching the recording action.
Apricot marks the recording action; slate carries financial values and forest marks the household identity.
The white bottom navigation reduces the amount of solid green on screen.
Financial detail expansion uses a short size transition and rotating chevron to explain the content change, disabled when reduced motion is requested.
Use the existing branch mark, real member initials, and relevant home, wallet, invitation, and location icons instead of unrelated imagery.
Functional Material icons identify destinations and account types, not decoration.
Reserve elevation for sheets and dialogs; separate list groups with whitespace.
Controls use 12–14 logical-pixel corners, containers 16–20, and avatars remain circular.
