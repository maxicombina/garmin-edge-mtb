# a-activity-timer

Connect IQ **data field** for Garmin Edge 830/840: activity timer with an adaptive display format — `M:SS` under one hour; from one hour on, `H:MM:SS` when the cell is large enough, `H:MM` when it is not.

This is **Option A** of the project spec (the tutorial project, Phase 0 of the roadmap) — see [`GARMIN_MTB_SPEC.md`](../../GARMIN_MTB_SPEC.md), section 4. It intentionally duplicates the native "Timer" field: the point is learning the full Connect IQ cycle (project skeleton, `compute()`/`onUpdate()`, adaptive rendering by text measurement, simulator, sideload) with logic that can be validated 1:1 against the native field.

## Status

Spec complete ([`SPEC.md`](SPEC.md)), verified against official Garmin docs on 2026-07-18. Implementation pending.
