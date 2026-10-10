# App History Field Selection Implementation Plan

**Goal:** Keep App telemetry history readable with remembered, grouped field selection.

**Approved design:** Common defaults; PV, battery, AC and system groups; selected fields only in expanded samples. Preserve chart/date/paging behavior, actual zero and unknown values. Preferences contain field identifiers only, not measurements or credentials.

**Architecture:** A catalog and bottom-sheet selector beside the existing history widgets. SharedPreferences uses one versioned display preference key. The page hydrates known nonempty identifiers and preserves a local edit if preference loading is late.

**Tech stack:** Flutter Material, existing localization, SharedPreferences, flutter_test.

1. Add regression tests for common defaults, group selection, persistence, cancel, malformed preferences and 320px large text.
2. Extract the existing 24 fields into a grouped catalog. Add a bounded, searchable selector with reset and explicit apply; prevent empty selection.
3. Render only selected fields under short group headings. Keep genuine zero values, null markers and exact integer codes.
4. Run focused/full Flutter tests, analyze, inspect actual widget screenshots, and build a new acceptance APK. No upload or installation.

Separate remaining acceptance: physical-phone PIN/WiFi, power-cycle debug, authenticated production telemetry, production signing and deploying this uncommitted batch.
