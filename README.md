# Whorkaround

A best-effort workaround for the missing `/who` on Project Epoch. Whorkaround builds a persistent database of players you encounter and lets you look them up by name — including offline players (shows cached "last seen" data) and enemy faction members (through "proxy" users that reply to your requests).


---

## How It Works

Every time you see another player — in combat, mousing over them, targeting them, or receiving a network response — Whorkaround quietly records their name, level, class, race, and zone. Over time this builds into a searchable local database you can query any time, even when those players are offline (showing cached/last seen data).

For players not yet in your database, Whorkaround can reach out to the network: other users running the addon will respond automatically with live data, including cross-faction lookups via proxy.

---

## Features

**Database Browser**
Accessible from the Social panel (the same window as the Friends list). Searchable and sortable — filter by name, class, or zone. Click any entry to query for a live update.

**Ambient Scanner**
Passively collects player data from the combat log, mouseover events, and tooltips with no noticeable performance cost. Runs in the background automatically.

**Network Lookups**
Looking up an enemy faction player triggers a proxy request: a community member on that side performs a live Friends List check on your behalf and sends the result back. Query any player by name with `/who Name`. If they were very recently cached in you DB, you'll see an instant result. If not, Whorkaround asks the network — other users respond automatically with live or cached data.

**Mention Links** *(optional, opt-in)*
Type `[Name]` or `@Name` in chat and Whorkaround will turn it into a class-coloured clickable player link. Toggle this on in Options if you want it.
This is disabled by default.

**Options Panel**
Accessible from the Friends List Who-tab. Configure proxy behaviour, database retention, and the Mention Links feature.

---

## Commands

| Command | What it does |
|---|---|
| `/who Name` | Query a player by name |
| `/whofind text` | Search your local database |
| `/whogui` | Open the Database Browser directly |
| `/whostats` | Show database totals |
| `/whocleardb` | Wipe your local database |
| `/whodebug` | Toggle debug logging |

---

## Compatibility

Designed for **Project Epoch** (WoW 3.3.5). Compatible with ElvUI and ElvUI Enhanced — if either is installed, Whorkaround will also pull class data from their internal caches.
