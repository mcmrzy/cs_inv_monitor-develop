# BMS Monitor Preview Implementation Plan

**Goal:** Make the approved BMS Web/mobile hierarchy reviewable and interactive.

**Architecture:** One isolated Vite HTML entry, shared simulated data and presentational
sections, distinct desktop/mobile layouts. No production API calls or route changes.

**Tech Stack:** Existing React, Ant Design icons/controls and ECharts wrapper.

## Task 1: Isolated preview

- [x] Create `inv-admin-frontend/bms-design.html` and `src/design/bms-preview.tsx`.
- [x] Add fixture-driven normal, alarm, expired and absent BMS states.
- [x] Add preview controls distinct from simulated product controls.

## Task 2: Product surfaces

- [x] Create `src/design/bms-preview.css` with independent desktop/mobile layouts.
- [x] Build summary, cell graph/selection, temperature, capacity and grouped alerts.
- [x] Add raw diagnostic disclosure; never invent units, thresholds or live history.

## Task 3: Verification and review

- [x] Start a local Vite server on an unused loopback port.
- [x] Use a real browser at desktop/mobile sizes; exercise controls and inspect errors.
- [x] Capture screenshots, verify chart pixels and no horizontal overflow.
- [x] Open preview in Codex and provide the local URL for design review.
- [x] After user review approval, integrate into `BmsTab.tsx` and Flutter `BmsSummaryView`.

No automatic commit, release, flash or deployment. Preserve the existing dirty tree.

## Verification result

`npx tsc -b --pretty false`: passed.
`node bms-design.verify.mjs`: passed, zero browser errors. Desktop 1440/1920
and mobile 320/390 widths checked. Cell chart has 26023 colored pixels. Cell
selection, protection-to-diagnostics navigation, uncertainty labels, stale-value
masking and the complete 100-byte historical raw payload were checked. Screenshots
are in `inv-admin-frontend/design-previews/` and visually inspected.

Preview URL: `http://127.0.0.1:5177/bms-design.html`. This entry is intentionally
not added to production build inputs. The user subsequently approved this design;
production implementation and verification are recorded in
`2026-10-08-bms-monitor-production.md`. The original HTML remains a design artifact,
while `bms-component-review.html` renders the actual production Web component.
