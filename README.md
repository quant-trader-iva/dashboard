# Trading Projection Dashboard v4

This version fixes the missing rows:

- Extreme at High
- Extreme at Low

They are now included:
1. In the New Entry form
2. In the main dashboard table
3. In the data export/import structure
4. In the Supabase schema and sync mapping

Correct range logic is still preserved:

- Weekly FR/HR/QR/ER uses Previous Weekly High and Previous Weekly Low.
- Daily FR/HR/QR/ER uses Previous Day High and Previous Day Low.
- London FR/HR/QR/ER uses Previous NY Day High and Previous NY Day Low.
- New York FR/HR/QR/ER uses Current London High and Current London Low.

Extreme at High / Extreme at Low are separate rows placed between New York Range and Projection FR.

## v4 fixes

- **Dashboard grid no longer drops data.** When Session Filter is "All", a single day can have Weekly/Daily/London/New York entries at once; the grid now creates one column per (date, session type) instead of one column per weekday, so no session is silently overwritten.
- **Current-session range breakdown.** Added Half/Quarter/Eighth rows computed from the session's own High/Low, separate from the Reference (previous-session) FR/HR/QR/ER breakdown.
- **Reference fields auto-fill and lock.** The New Entry form only shows the reference High/Low pair relevant to the selected Session Type, and auto-fills it from the matching prior saved session (previous Weekly, previous Daily, previous New York, or same-day London) — locking the fields to prevent typos. If no matching prior session exists yet, the fields stay editable.
- Storage keys, title, and export filenames now consistently say v4 (existing v3 local data is migrated automatically on first load).
