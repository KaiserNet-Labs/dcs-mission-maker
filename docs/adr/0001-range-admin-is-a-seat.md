---
status: accepted
---

# Range Admin is a seat, not a list of players

In a Training Range, a Range Admin is whoever sits in the Range Control flight. There is no list of admin DCS account IDs (UCIDs). A DCS dedicated server has no admin list that scripts can read, and the server hook (the only code that can see UCIDs) is optional and still untested inside DCS. We wanted admin features to work without the hook. A Range Control *aircraft* flight is used rather than a Game Master seat for two reasons: Game Master seats need Combined Arms, and F10 menus can only be shown to aircraft groups.

## Considered Options

- **UCID list in the app's Settings, enforced by the hook.** Secure, but nobody is admin unless the hook is installed and working.
- **Range Control on the red coalition, behind DCS's coalition password.** Locked without the hook, but admins would fly as the enemy side.
- **Chat password (`-admin <pw>`).** Needs the hook, the same as the UCID list.

## Consequences

- Without the hook, anyone can take a Range Control seat (honour system). With the hook, a password is needed before taking the seat.
- Admin rights last as long as someone sits in the seat. Leaving it removes them.
