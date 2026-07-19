# a-activity-timer

Connect IQ **data field** for Garmin Edge (830/840 + 11 more): an activity timer with an adaptive display format — `M:SS` under one hour; from one hour on, `H:MM:SS` when the cell is wide enough, a compound `H:MM` + raised `:SS` superscript when narrower, and bare `H:MM` when tighter still. A small stopwatch glyph sits next to the label.

This is **Option A** of the project spec (the tutorial project, Phase 0 of the roadmap) — see [`GARMIN_MTB_SPEC.md`](../../GARMIN_MTB_SPEC.md), section 4. It intentionally duplicates the native "Timer" field: the point is learning the full Connect IQ cycle (project skeleton, `compute()`/`onUpdate()`, adaptive rendering by text measurement, simulator, sideload) with logic that can be validated 1:1 against the native field.

## Status

**Phase 0 complete — in beta.** Implemented, tuned pixel-perfect against the native field on a real Edge 840, and published as a beta (`v0.1.6`) on the Connect IQ Store. Full contract in [`SPEC.md`](SPEC.md) (verified against official Garmin docs); code walkthrough in [`docs/code-walkthrough.html`](docs/code-walkthrough.html).
