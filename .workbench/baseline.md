# Baseline: known Findings

From the Full Trial of 2026-11-17 09:31 (.workbench/trials/2026-11-17-0931), commit 0190dd0.

## Summary
The code is generally careful. Routes check their inputs, there are no injection, path-traversal or password-bypass bugs, the settings page is protected against DNS rebinding, and vendored downloads are verified by hash. The one blocking problem is the Pillow 11.* pin. The scan's advisories include several that hit exactly what the public kneeboard upload does: the GIF and animated PNG problems sit in `Image.open` itself, before the format check runs; the BMP RLE problem is in `load()`; the PNG eXIf problem is in `exif_transpose`. That upload stays open with APP_PASSWORD set and sits on the README's Cloudflare bypass path (`api/missions/*`). The other confirmed rulings are one Medium race in event sign-ups and a set of Low robustness and supply-chain hardening items. Three Findings were dismissed: one was factually wrong (the "dead" `save_ico` is used by the PyInstaller spec), and two describe documented design. The project tests were not run in this Trial, so no ruling relies on test results.

## Verdict
NOT CLEAN: 1 blocking (F-1); 1 Medium, 14 Low confirmed; 3 dismissed. Fit to release once F-1 is fixed and the kneeboard tests pass on the new Pillow.

## Rulings
| ID | Findings | Ruling | Severity | Location | What | Reasoning |
|---|---|---|---|---|---|---|
| F-1 | SUP-1, ATK-1, OPS-1 | Confirmed | High | requirements.txt:7; app/kneeboard_store.py:305-316 | Pillow pinned to 11.*, and the public kneeboard upload decodes attacker images | Advisories in pip-audit hit code paths the upload uses (APNG, GIF, BMP RLE, PNG eXIf via exif_transpose); the endpoint is public even with a password and on the documented Cloudflare bypass; the pin blocks every fix |
| F-2 | MNT-1 | Confirmed | Medium | app/server.py:536-577, 408-409 | Event claims and event_generate change the event unlocked and save a stale copy non-atomically | Code matches: no `_locked`, stale `ev` saved after `build_and_store`, plain `write_text` |
| F-3 | MNT-2, OPS-4, TST-2 | Confirmed | Low | app/server.py:598-607 | reports.json is changed unlocked, not atomically, trimmed by insertion order, and accepts any .miz name | Verified; reports are advisory |
| F-4 | TST-1 | Confirmed | Low | app/debrief.py:31-45; app/server.py:598-607, 690-703 | Malformed bodies on the open hook endpoints raise 500s | `int(...)` unguarded, `.items()` on a list, list body passes `or {}` |
| F-5 | TST-4 | Confirmed | Low | app/kneeboard_store.py:337; app/server.py:907-939 | Zero-size PDF page divides by zero; shared library is guarded only by the per-mission lock | Library race is verified; ZeroDivision follows from the code but was not reproduced |
| F-6 | OPS-3 | Confirmed | Low | app/server.py:291-326; app/mission_store.py:34-40, 86 | A crash mid-build leaves a meta-less .miz that is treated as kept and never expired | Verified in status() and cleanup() |
| F-7 | OPS-2 | Confirmed | Low | app/integrations.py:104-121 | SFTP Transport has no connect timeout and is not closed on failure | `close()` only on the success path |
| F-8 | ATK-3 | Confirmed | Low | app/integrations.py:107-114 | SFTP accepts any host key unless SFTP_KNOWN_HOSTS is set | Optional per README:103; a hardening gap, not a bypass |
| F-9 | SUP-2 (and paramiko part of OPS-1) | Confirmed | Low | requirements.txt:10 | paramiko 3.* cannot get the PYSEC-2026-2858 fix (SHA-1 allowed in rsakey) | Narrow: SFTP only |
| F-10 | ATK-4 | Confirmed | Low | app/server.py:97-106 | No throttle on Basic-auth attempts | Real; README directs exposed installs behind a proxy or Access |
| F-11 | TST-3 | Confirmed | Low | tests/api.py:288-303 | No structural test of the PUBLIC_ENDPOINTS allowlist | Allowlist is default-deny, so this is a coverage gap rather than a hole; downgraded from Medium |
| F-12 | SUP-7 | Confirmed | Low | app/templates/index.html:7-8; briefing.html:7-8 | Leaflet from unpkg without SRI | Verified; needs a CDN compromise |
| F-13 | SUP-3 | Confirmed | Low | requirements.txt; requirements-build.txt; ci.yml | Ranged pins, no lock or hashes, floating eslint in CI | Hygiene; downgraded from Medium |
| F-14 | SUP-4 | Confirmed | Low | .github/workflows/*.yml | Actions on mutable tags; unpinned choco innosetup | Hardening; write scope is already narrow |
| F-15 | SUP-6 | Confirmed | Low | .github/workflows/windows.yml:27-30 | `${{ github.ref_name }}` inside a pwsh double-quoted string | Needs push access; trivial env: fix |
| F-16 | SUP-5 | Confirmed | Low | Dockerfile:1,15 | Base image by tag; no provenance, signature or SBOM | Best-practice gap |
| F-17 | MNT-3 | Dismissed | | app/icon.py:20 | "save_ico is never called" | False: windows/dcs-mission-maker.spec:12 imports it and line 51 calls it |
| F-18 | MNT-4 | Dismissed | | tools/build_liveries.py:8,17 | Unchecked SHA256 constant | The docstring makes the check manual by design; dev-only tool, not shipped; pin matches fetch_vendor today |
| F-19 | ATK-2 | Dismissed | | app/server.py:907; app/kneeboard_store.py:374-399 | Seat holders can add to or remove from the squadron library | By design: README:150 documents seat holders saving to and removing from the library; links are not secret per the Owner's notes |

## Reasoning on contested points
- **F-1 (Skeptic proposed Medium, SUP-1 filed High):** I checked the advisories in scans/pip-audit.json against the code instead of relying on the count. `decode()` calls `Image.open` with no `formats=` and checks the format only afterwards. CVE-2026-112401 (quadratic GIF comment) and CVE-2026-112399 (126-byte APNG allocating about 1.9 GB before the bomb check) both trigger inside `Image.open`. CVE-2026-96638 (BMP RLE) triggers in `load()` on an allowed format. CVE-2026-96643 (PNG eXIf) triggers in `exif_transpose`, which `decode()` calls. The `DecompressionBombWarning` filter does not cover these. Re-encoding to PNG happens after decoding, so it is no mitigation. Each request may carry 10 files, and the README's Cloudflare bypass includes `api/missions/*`. A tiny-file memory denial of service against an endpoint that is unauthenticated by design is shown, not speculative, so High stands. I did not credit memory-corruption claims: CVE-2026-112403 needs `draft()`, and `_fit` calls `convert()` before `thumbnail()`, so draft never runs.
- **F-17 (MNT-3, conceded by the Skeptic):** Overruled both. A grep finds `from app.icon import save_ico` and `icon=save_ico(...)` in windows/dcs-mission-maker.spec. The Maintainer's statement that it grepped the spec is wrong.
- **F-19 (ATK-2):** The Skeptic's "by design" point holds. README:150 explicitly lets seat holders save pages to the library and remove them from it, and the Owner accepts that links are not secret.
- **F-11:** Agreed with the Skeptic. A default-deny allowlist means a missed route fails closed, so Low.
- **F-4:** The Skeptic said the flags loop is guarded. Only `int(v)` is guarded; `.items()` on a non-dict raises, so the Tester's AttributeError case stands.
- **F-9 vs F-8:** These are kept as separate rulings (the library advisory and the host-key config are different fixes) but share a card in the brief.

## Recommended fix order
1. requirements.txt: `pillow>=13,<14`. In app/kneeboard_store.py `decode()`, pass `formats=list(IMAGE_FORMATS)` to `Image.open` and lower `Image.MAX_IMAGE_PIXELS`. Re-run tests.api and tests.smoke in the image (F-1).
2. app/server.py: in `claim_seat` and the end of `event_generate`, use `_locked(f"event-{eid}")` and reload before saving. Make `_save_event` write atomically. In the same change, lock `add_report`, write it atomically, use pop-then-insert, and check the .miz exists (F-2, F-3).
3. app/debrief.py `merge()` and server.py `add_report`/`add_debrief`: type checks and a 400 on bad input. Add a zero-size guard in `_decode_pdf` and a library-wide lock in kneeboard_store (F-4, F-5).
4. app/server.py and mission_store.py: write the meta file at claim time, or clean up meta-less empty .miz files (F-6).
5. app/integrations.py `publish_sftp`: `socket.create_connection(..., timeout=15)`, try/finally close, and a warning or refusal without known_hosts. Test paramiko 5 (F-7, F-8, F-9).
6. tests/api.py: a url_map walk test (F-11). server.py: failure throttle (F-10). Templates: SRI hashes (F-12).
7. Supply chain, in one change: lock file with hashes, SHA-pinned actions, env-passed ref_name in windows.yml, base image digest, Dependabot (F-13 to F-16).

## Known issues baseline
- F-1 (SUP-1, ATK-1, OPS-1): Pillow pinned to 11.*; the public kneeboard upload decodes untrusted images with known DoS advisories in the GIF, APNG, BMP and eXIf paths.
- F-2 (MNT-1): event claim_seat and event_generate change the event unlocked, can save a stale copy, and save non-atomically.
- F-3 (MNT-2, OPS-4, TST-2): reports.json is changed unlocked and non-atomically, evicted in insertion order, and accepts any .miz name.
- F-4 (TST-1): malformed bodies on /api/debrief and /api/reports raise 500s.
- F-5 (TST-4): zero-size PDF page gives ZeroDivisionError; the squadron library has no library-wide lock.
- F-6 (OPS-3): a crash mid-build leaves a meta-less .miz, treated as kept and never expired.
- F-7 (OPS-2): SFTP has no connect timeout, and the transport is not closed on failure.
- F-8 (ATK-3): SFTP host key is not verified without SFTP_KNOWN_HOSTS.
- F-9 (SUP-2): paramiko 3.* cannot get the PYSEC-2026-2858 fix.
- F-10 (ATK-4): no throttle on APP_PASSWORD attempts.
- F-11 (TST-3): no structural test of the PUBLIC_ENDPOINTS split.
- F-12 (SUP-7): Leaflet from unpkg without SRI.
- F-13 (SUP-3): ranged pins, no hash lock, floating eslint in CI.
- F-14 (SUP-4): workflow actions on mutable tags; unpinned innosetup.
- F-15 (SUP-6): ref_name interpolated into pwsh in windows.yml.
- F-16 (SUP-5): Docker base image by tag; no provenance, signing or SBOM.

Record notes: no rule departures observed. The Clerk's own MNT-4 confidence slip was corrected before the defense and did not affect the ruling. Project tests were not run in this Trial (scans/tests.txt). I ran only read-only commands and one in-memory `python3 -B` read of scans/pip-audit.json, and wrote no files.

Relevant paths: /home/clanker/projects/dcs-mission-maker/requirements.txt, /home/clanker/projects/dcs-mission-maker/app/kneeboard_store.py, /home/clanker/projects/dcs-mission-maker/app/server.py, /home/clanker/projects/dcs-mission-maker/windows/dcs-mission-maker.spec, /home/clanker/projects/dcs-mission-maker/.workbench/trials/2026-11-17-0931/
