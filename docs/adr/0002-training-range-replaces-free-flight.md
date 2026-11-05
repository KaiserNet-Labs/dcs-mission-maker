---
status: accepted
---

# Training Range replaces Free Flight

The Training Range mission type replaces the old "Free Flight / Training" type (`free`) instead of sitting beside it. A Training Range with nothing spawned is already an empty sky with player slots, so keeping both would mean two nearly identical types to maintain. The one real difference is that Free Flight gave everyone air-to-air loadouts, and that is now handled by each flight's Flight Role.

## Consequences

- Saved setups, sign-up pages (including weekly repeats) and builder code that use `mission_type: "free"` must be moved to the Training Range type. Old requests should be mapped rather than rejected. `app/static/js/builder.js` references `free`.
- Anyone who wants a plain free flight builds a Training Range and simply doesn't spawn anything.
