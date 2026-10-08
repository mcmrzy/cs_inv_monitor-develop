# BMS monitoring page design

Approved direction: status overview with layered diagnostics. Deliver a reviewable
Web and mobile prototype before replacing production views. All prototype values
are explicitly identified as simulated outside the product surfaces.

## Information hierarchy

1. Communication freshness, SOC, pack voltage/current, SOH and active alerts.
2. Cell consistency: all 16 slots, actual max/min and spread, balance markers,
   selection details. Missing slots remain missing, never zero.
3. Temperatures, capacities and cycles grouped by purpose.
4. Separate warning/protection/fault groups. Charge/discharge and MOS status bits
   are operational states, not faults. No invented safety thresholds.
5. Collapsible diagnostic details: original enums, uncertain-unit quantities,
   timestamps and complete raw payload. SOC/SOH scaling remains provisional.

## Responsive behavior

Web: dense scan-friendly summary, side-by-side cell and status analysis, tabular
details. Retain the existing device navigation and Ant Design icon vocabulary.
Mobile: one-column content with overview/cells/diagnostics navigation; compact
two-column metrics, generous touch targets and selection details below the chart.
Use restrained neutral surfaces, green availability, amber warnings, red
protection/faults and blue minimum-cell markers. Do not infer health from a color
threshold that the protocol does not define.

## States

Normal, warning/protection, offline/stale and not-connected preview fixtures.
Expired data cannot appear as live values. Raw last snapshots remain inspectable
with historical labels. Unpopulated temperature fields show unavailable, not 0 C.
The product must distinguish device online status from BMS link availability.

## Acceptance

Review both surfaces and interactive state/cell/details controls. Check 320/390 px
mobile, 1440/1920 px desktop, browser errors, graph pixels and horizontal overflow.
Production integration follows review; this prototype does not change firmware,
database, telemetry or production routes, and does not claim hardware validation.
