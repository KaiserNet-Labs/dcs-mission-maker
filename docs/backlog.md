# Backlog

Known issues waiting for a fix, oldest first. Each line names where it came from.

## From Full Trial 2026-11-17-0931 (F-3 to F-16; all Low, none blocks a Release)

F-1 (Pillow 11 on the open kneeboard upload) and F-2 (sign-up races) were fixed before the first Release from the Box.

| ID | Where | What | Suggested fix |
|---|---|---|---|
| F-3 | app/server.py `add_report` | `reports.json` is changed without a lock and not in one step; the 200-entry trim drops by insertion order; any `.miz` name is accepted | Lock and write atomically, pop-then-insert, accept only missions that exist |
| F-4 | app/debrief.py `merge`; server.py `add_report`, `add_debrief` | Malformed bodies on the open hook endpoints (`/api/debrief`, `/api/reports`) raise 500s | Type checks, 400 on bad input |
| F-5 | app/kneeboard_store.py `_decode_pdf`, library | A zero-size PDF page divides by zero; the squadron library has only the per-mission lock | Zero-size guard; a library-wide lock |
| F-6 | app/server.py build; mission_store.py | A worker killed mid-build leaves a `.miz` with no meta file, treated as kept and never expired | Write the meta file at claim time, or let cleanup remove meta-less empty files |
| F-7 | app/integrations.py `publish_sftp` | No connect timeout; the transport isn't closed on failure | `socket.create_connection(..., timeout=15)`, try/finally close |
| F-8 | app/integrations.py `publish_sftp` | Any host key is accepted unless `SFTP_KNOWN_HOSTS` is set | Warn or refuse without a known-hosts file |
| F-9 | requirements.txt | paramiko 3.* can't get the PYSEC-2026-2858 fix (SHA-1 in rsakey) | paramiko 5 after testing SFTP |
| F-10 | app/server.py auth | No throttle on `APP_PASSWORD` attempts | Delay after failures, or advise a long password on Settings |
| F-11 | tests/api.py | No structural test of the `PUBLIC_ENDPOINTS` split | One test walking `url_map` with a password set |
| F-12 | app/templates/index.html, briefing.html | Leaflet from unpkg without SRI | Integrity hashes, or ship Leaflet with the app |
| F-13 | requirements*.txt, ci.yml | Ranged pins, no hash lock, floating eslint in CI | Hash-locked requirements, pinned eslint |
| F-14 | .github/workflows/*.yml | Actions on mutable tags; unpinned innosetup | Pin actions by SHA, pin innosetup |
| F-15 | .github/workflows/windows.yml | `${{ github.ref_name }}` inside a pwsh double-quoted string (needs push access) | Pass it through `env:` |
| F-16 | Dockerfile | Base image by tag; no provenance, signing or SBOM | Pin the base image by digest; provenance later |

## From Diff Trial 2026-11-17-1008 (base `0190dd0`, CLEAN at `5b4bc5e`, the v1.2.2 commit; all Low)

IDs are this Trial's own, so they're written 1008/F-n to keep them apart from the table above.

| ID | Where | What | Suggested fix |
|---|---|---|---|
| 1008/F-1 | app/server.py `claim_seat`, `_locked`, `delete_event` | The open claim route creates `.event-<id>.lock` and a lock entry for any well-formed id before the 404; event lock files are never removed | Check the event exists before taking the lock; remove the lock file in `delete_event` |
| 1008/F-2 | app/server.py `delete_event`, `_roll_over` | `delete_event` isn't under the event lock, so a racing claim or generate can bring a deleted event back; a deleted next occurrence can make `list_events`/`get_event` 404 during the roll-over announcement | Delete under the event lock; let `_roll_over` treat a vanished next occurrence as gone |
| 1008/F-3 | tests/api.py; app/kneeboard_store.py `decode` | No positive upload test for WebP, GIF or BMP, and no boundary test at the 25 MP cap, after the Pillow 11→13 move | Upload one of each; a 25 MP image passes the cap and 25 MP + 1 doesn't |

## Questions for the Owner

- **Allow MPO uploads?** Some phones and cameras save JPEGs that Pillow reads as MPO (a JPEG with extra frames). The kneeboard upload refuses them, as it did before the Pillow 13 change. Allowing them means adding `"MPO"` to `IMAGE_FORMATS` in `app/kneeboard_store.py` (the JPEG decoder reads them; only the first frame is used), plus a test. Not decided; no change made.

## Notes

Not a Trial Finding: a claim made while an event's mission is being built is now kept on the sign-up sheet, but it isn't in that `.miz`. Generating again picks it up.
