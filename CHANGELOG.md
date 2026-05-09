# Changelog

All notable changes to this project will be documented in this file.

## [1.5.6] - 2026-05-09

### Fixed

- **Ghost Friend Cleanup:** Temporary friends are now tracked in a local database, so if you log out or close the game before a query finishes, it should still clean them up on your next login. In case of a crash/disconnect, it should instead catch friends added by Whorkaround through a `Whorkaround:tag` note on any friends it adds.
- **Emergency Purge:** Whorkaround now instantly blocks all new queries if it sees a 20-second logout timer, and attempts to wipe all temporary friends right as the game closes.  
- **Chat Spam Fix:** Fixed an edge-case where aborted proxy queries (like when someone else answers the request first) would end up printing "removed from friends list" to chat.  
- **Nameplate Scanner Improvements:** Added strict type-checking and a 3-step fallback system to the Nameplate scanner. This should fix Lua crashes and errors when Nameplate addons (like Kui Nameplates) heavily modify or delete default nameplate elements. (Should fix [#2](https://github.com/ZythDr/Whorkaround/issues/2))  

## [1.5.5] - 2026-05-07

### New

- **Native WIM / LibWho Support:** Merged the experimental LibWho bridge directly into the core addon! Whorkaround will now natively intercept background `/who` lookups requested by addons like WIM (WoW Instant Messenger), seamlessly feeding them live, corrected player data from the local database. If WIM doesn't know a player's exact race, it now smartly falls back to displaying their faction (Alliance/Horde) instead of leaving it blank. It "just works" right out of the box with zero configuration!

### Fixed

- **Silent Queries Dropping Data:** Fixed a bug where background `/who` lookups (like those triggered by WIM or other addons using `silent=true`) were skipping the database save phase if the player was found instantly (e.g. already on your friends list). Background lookups now properly and silently update the database cache.
- **Cross-Faction Scanner Fix:** Ripped out flawed logic in the Nameplate and Combat Log scanners that assumed red/hostile players were always the enemy faction and blue/friendly players were always your faction. This fixes major database corruption issues caused by duels, FFA arenas, or cross-faction groups (like on Project Epoch).
- **Smart Group Faction Detection:** The nameplate scanner now checks if a friendly player is in your party or raid group to accurately extract their true faction via group unit tokens, instead of guessing based on their healthbar color.

## [1.5.4] - 2026-05-05

- **Public API:** Added `WhorkaroundAPI` for companion addons — `Query`, `Refresh`, and `GetEntry` to interact with the DB without touching internals.

### Fixed

- Silent background queries (mention pre-queries, etc.) now give up cleanly after the network timeout instead of retrying indefinitely.

## [1.5.3] - 2026-05-03

### New

- **Guild Roster Scanner:** On login, the addon now quietly scans your guild roster and populates the DB with class and level for recently-active members. Offline members who haven't been online within your configured "Purge after" window are skipped, so inactive players don't get recycled back into the DB. When a guildmate logs in or out mid-session, it re-scans to keep zone and last-seen data fresh. Throttled to 5 entries per frame so large guilds cause no stutter.
- **Nameplate Scanner:** Passively reads visible nameplates to pick up player data you'd otherwise only get by mousing over them. Runs on a 0.1s tick, processes one nameplate per tick, so it should have no percievable performance impact. For enemy players it decodes class from the health bar colour (same method ElvUI uses). For group members it uses the unit token directly. Friendly strangers get name, level, and faction but no class — that still requires a mouseover or combat log event. Players are re-scanned at most once every 30 seconds.

### Fixed

- ElvUI class lookups were writing player names with original capitalisation as DB keys (e.g. `"Blame"`) instead of lowercase, causing duplicate rows in the browser (e.g. "Blame" appearing twice). Fixed. A one-time DB migration on load will merge any existing duplicates, keeping whichever entry is newer.
- Clicking Refresh too quickly could temporarily blank the browser list with "0 People Found" because Blizzard injects "- Please Wait -" into the search box while a server query is in-flight. The browser now ignores that string and keeps the current list visible.
- Typing `[Name]` or `@Name` in chat was firing a network pre-query on every keystroke if the name wasn't in the DB yet, causing repeated `WKR:H:name` channel messages. Now queries at most once per name per time the chat box is open.

### Improved

- Background scanner updates (combat log, tooltip, guild scan) no longer trigger an immediate browser redraw each time. They now coalesce into a single redraw on the next game frame, so a burst of 10 scanner hits only redraws the list once.
- Tooltip re-scans of the same player are now gated to once every 30 seconds per player.
- Browser redraws are skipped entirely when the WhoFrame is closed — the DB still updates silently in the background.

## [1.5.2] - 2026-05-02

### Fixed

- Clicking Refresh on a cached DB entry could crash with a nil error in the sort dropdown. Fixed.
- Network replies were sometimes silently ignored if the addon already had a newer record for that player locally, causing "No community data was found" even though someone responded. Fixed.

## [1.5.1] - 2026-05-02

### Fixed

- Squashed a crash that could occur when the Ambient Scanner had seen a player but couldn't pin down their level yet. A few spots in the network layer weren't expecting that and tripped over it.

## [1.5.0] - 2026-05-02

### New

- **Ambient Scanner:** Passively collects player info (level, class, race, zone) from the combat log and mouseover/target events with zero FPS cost. On by default for new installs.
- **Mention Links module:** `[Name]` and `@Name` in chat can now be turned into class-coloured clickable player links. Opt-in toggle in Options, off by default. Shift-clicking a player link with the chat box open pastes their name into it (plain name normally, `[Name]` syntax when Mention Links is on).
- **DB Browser improvements:** Hover tooltips show a cleaner layout (Name → Guild → Level/Race/Class → Zone → Faction → Last Seen → Source), with human-readable source labels ("Combat Log", "Tooltip", "Network", etc.).
- **Smart WhoFrame Refresh button:** Refreshing a selected same-faction player goes through the normal query pipeline; cross-faction fires a network proxy request.

### Changed

- New install defaults: Proxy Mode on (Out of Combat only), 15s cooldown, Ambient Scanner on.
- Dropdown menus in Options are now consistent — all use `ToggleDropDownMenu` so a second click closes them.
- Enable Debug and its verbosity button moved to the bottom-right of the Options panel alongside the DB Stats cluster.

### Fixed

- Shift-clicking a player name in chat no longer sends a visible `/who` query when the chat edit box is open.
- Spell names (e.g. `[Mutilate]` from shift-clicking a spell) no longer get picked up as player name mentions, preventing an infinite `/who` loop every ~3 seconds.
- Two `GetWhoInfo` / `GetNumWhos` crashes specific to Epoch's client build: one when opening the Friends panel with no prior `/who` results, one when the Who frame was idle and `FriendsFrame_Update` fired.
- Add Friend and Group Invite buttons now correctly enable/disable based on the selected DB entry.
- Left-clicking a DB entry no longer causes the list to scroll back to the top.
- Combat log entries now survive a `/reload` instead of being pruned on startup.

## [1.4.25] - 2026-05-01

### Fixed

- **UI Taint / Action Blocked Fix:** Removed the experimental editbox colorization and hyperlink injection feature. While visually cool, it caused secure execution errors (Taint) when combined with other addons or macros. Stability is now restored to 100%.

## [1.4.24] - 2026-05-01

### Core Engine & Performance

- **No more "phantom" chat prints:** Rewrote the background lookup logic to properly track state and block random events from leaking into your chat window.
- **Instant typing detection:** Removed the 0.3s delay when typing names in chat. It now detects mentions instantly while using a trailing space to keep network usage low.

### Chat & Visuals

- **Better @mentions & colored typing:** `@Names` now stay as `@Names` instead of turning into brackets. They also now show up in class color directly in the chat box while you're typing or shift-clicking.
- **Safe link stripping:** Added a filter that automatically cleans up our hidden link data before you send a message, so the server doesn't strip or block your text.

### Bug Fixes

- **Color & Timeout fixes:** Fixed a bug where players could show up as the wrong class color on some realms and added a 5-second "emergency" timeout so failed scans don't hang.
- **Debug toggle fix:** Made sure debug logs actually listen to the toggle in the GUI settings.

## [1.4.23] - 2026-04-30

### Fixed

- Chat Leaks: Resolved an issue where automated background lookups (triggered by names in brackets or @ mentions) would occasionally print results to the user's chat.
- Proxy Stability: Improved silent mode handling to ensure proxy requests remain strictly invisible to the proxying user.

## [1.4.22] - 2026-04-30

### Fixed

- Backward Compatibility: Fixed a parsing bug where network requests from older Whorkaround clients (versions before 1.4.15) were being incorrectly processed, causing names to be truncated and occasionally triggering ghost lookups and chat spam on the receiving end.

## [1.4.21] - 2026-04-30

### Added

- Debug Mode: Added an "Enable Debug" toggle to the Whorkaround Options panel. When enabled, this prints all background actions (network requests, proxy decisions, and database cleanups) directly to your chat window to help verify that the addon is functioning and communicating properly.

## [1.4.19] - 2026-04-30

### Changed

- Chat Lookups: `@Name` and `[Name]` chat lookups are now much more reliable. The addon correctly waits for you to finish typing and press space before scanning the player.
- Silent Updates: Typing `@Name` will now run a full background scan (including cross-faction requests) to refresh their data entirely silently, without spamming your chat log with results.
- Network Traffic: Suppressed automatic network broadcasts for background cache hits to reduce overall network noise.

### Fixed

- Client Compatibility: Fixed a bug that caused the chat editbox lookups to fail silently on the 3.3.5 client.

## [1.4.18] - 2026-04-30

### Changed

- Memory Efficiency: Overhauled the core engine and GUI to eliminate memory "climbing" and high garbage buildup. Memory usage is now significantly lower and more stable during long sessions.
- Browser Performance: Implemented a table recycling system for the Database Browser, making it much faster and lighter when searching or hovering players.
- UI Clarity: Updated faction counters in the Browser to "Cached Alliance/Horde" to clarify they represent local database records.

### Fixed

- Data Accuracy: Resolved several issues where online friends, guild members, or targets would incorrectly show as "Cached" with old timestamps instead of "Live".
- Network Transparency: Refined proxy tagging logic to ensure players are only identified as proxy peers when performing actual cross-faction lookups.

## [1.4.17] - 2026-04-30

### Changed

- Proxy Tracking: Enhanced proxy peer detection. Anyone replying with a proxy-tagged response (:P) is now automatically counted as a proxy peer, improving network statistics.
- Relative Time Precision: Overhauled the relative time logic to handle clock drift between players. Events under 60s now show as 'just now' instead of '1 min ago', and all time units now use strict floor rounding for accuracy.

### Fixed

- Stale Data Reporting: Fixed a bug where results from previous network searches could incorrectly appear as 'Live' data for new searches.
- Timestamp Integrity: Resolved an issue where offline players would falsely appear as 'just now' sighted during network timeouts due to improper timestamp defaulting.
- Network Fallback Clarity: Updated chat output to clearly distinguish between successful network fetches and local cache recoveries.
- Timeout Data Restoration: Fixed a missing timestamp in the timeout handler that caused cached results to show as '(Unknown)' instead of their actual age.

## [1.4.16] - 2026-04-30

### Fixed

- Critical Lua Error: Resolved a 'bad argument #1 to unpack (table expected, got nil)' error in ElvUISkin.lua that prevented the GUI from loading for users without ElvUI enabled.

## [1.4.15] - 2026-04-30

### Changed

- Proxy Tracking: Enhanced proxy peer detection. Anyone replying with a proxy-tagged response (:P) is now automatically counted as a proxy peer, leading to more accurate network statistics.

## [1.4.14] - 2026-04-30

### Changed

- Query Responsiveness: Reduced manual query and shift-click cooldowns to 2 seconds for a snappier feel.
- Network Coverage: Enabled proactive broadcasting for all player detection paths, including target matches, guild roster hits, and chat hovers. Every interaction now helps populate the network database.
- Global Request Timing: Reduced global network request cooldown to 10 seconds.

### Fixed

- Network Timeout Visibility: Added an explicit 'No data found' message when network scans time out without results, resolving silent failures.
- Broadcast Integrity: Fixed a bug where manual same-faction lookups were printing locally but failing to share data with the network.

## [1.4.13] - 2026-04-30

### Added

- Browser Refinement: Added class-coloring to the 'Class' column in the database browser when 'Faction Colors' is enabled, providing a richer, data-dense view.

### Changed

- UI Ergonomics: Implemented a centered 'stat pill' design for faction counters in the Blizzard skin, featuring a vertical separator and outward-growth anchoring.
- ElvUI Mirroring: Relocated the 'Faction Colors' toggle to a mirrored top-left position when ElvUI is active to better suit its header layout.
- Professional Formatting: Standardized all class names to Title Case (e.g., 'Shaman' instead of 'SHAMAN') across the UI, database, and network protocols.
- Options Layout: Tightened the settings panel columns for a more centered and balanced appearance.

### Fixed

- Cross-Faction Requests: Resolved a critical bug where failed /who queries would cause requests to be incorrectly tagged with the sender's faction, preventing enemy data from being fetched from appropriate proxies.
- Data Integrity: Implemented a strict zero-tolerance policy for incomplete data. The addon now blocks any broadcasts or incoming messages containing 'Unknown' placeholders or invalid levels.
- Proxy Privacy: Background proxy lookups are now completely silent for the performer, ensuring the network engine works invisibly without printing result spam to the proxy user's chat.
- UI Stability: Fixed potential nil-value errors in faction detection during login and UI reload transitions.

## [1.4.12] - 2026-04-29

### Fixed

- Critical Lua Error: Fixed a crash in the results printer caused by an incorrect function call during friend removal checks.
- Chat Shift-Click: Restored the ability to insert player names into the chat editbox when it is active. Shift-clicking will now only trigger a /who query if the chat input is closed.

## [1.4.10] - 2026-04-28

### Changed

- Responsive Networking: Lowered the global request throttle to 30 seconds, making manual scans much more reliable when multiple users are querying the same player.

### Fixed

- Universal Title-Casing: Enforced proper name capitalization across all output paths in the chat window, including faction fallback messages.
- Network Request Debugging: Added debug logging for throttled requests to provide better visibility during troubleshooting.

## [1.4.9] - 2026-04-28

### Fixed

- Friend List Cleanup: Resolved an issue where temporary proxy friends were not being removed. Fixed by using proper 3.3.5 API indices for tagging and removal, and implementing backward iteration for cleanup loops.
- Note Tagging: Corrected the friend tagging logic to ensure the Whorkaround:Tag is applied correctly to all background queries.

## [1.4.8] - 2026-04-28

### Changed

- Proxy Response Speed: Reduced the delay for proxy lookups to 0.2s-1.2s for a snappier network feel.
- Broadcast Etiquette: Implemented a strict anti-echo policy where incoming network data throttles local broadcasts for that target, preventing chain-reaction duplicates.
- Strict Local Broadcasting: The addon will now only initiate a broadcast if the data was collected from a local source (Friends List, Sighting, etc.).

## [1.4.7] - 2026-04-28

### Fixed

- System Spam: Fixed "Player not found" error messages leaking into chat during background proxy lookups.
- Network Deduplication: Implemented global request tracking to prevent redundant WKR messages if another user has already requested the same target.
- Broadcast Rules: Tightened rules to prevent immediate re-broadcasting of data just received from the network.

## [1.4.6] - 2026-04-28

### Fixed

- Cross-Faction Proxying: Enforced a strict faction check for live proxy lookups. Users will now only attempt a background /who if the target's faction matches their own.

## [1.4.5] - 2026-04-28

### Fixed

- Lua Error: Fixed a critical nil value error in Comm.lua by restoring the missing Whorkaround:Log and ToggleDebug utility functions.

## [1.4.4] - 2026-04-28

### Fixed

- Proxy Invisibility: Network replies provided by the user as a proxy are now silent and won't appear in the proxy user's chat.
- Duplicate Broadcasts: Live proxy hits now correctly cancel scheduled cached broadcasts for the same target, preventing redundant network messages.
- Name Formatting: Enforced proper title-casing (capitalized first letter) for player names in all UI outputs and network broadcasts.

## [1.4.3] - 2026-04-28

### Fixed

- Shift-Click Chat Links: Fixed an issue where shift-clicking a player name in chat would trigger a /who search instead of inserting the name into the chat editbox.
- Improved EditBox Detection: Enhanced compatibility with ElvUI and other custom chat addons to ensure name links are correctly inserted into the active chat window.

## [1.4.2] - 2026-04-28

### Fixed

- Navigation Stability: Resolved an issue where users could become "trapped" in the Who tab after switching social categories.
- UI Persistence: Fixed a bug where the "People Found" counter would be overwritten by native Blizzard updates.

## [1.4.1] - 2026-04-28

### Added

- ElvUI Skinning Support: A new dedicated skinning module that provides a native ElvUI look for the database browser and options.
- Enhanced Options Readability: Implemented a "Double Dark" background for the options panel when ElvUI is detected, significantly improving contrast and readability.
- Colorized Addon Title: The addon now appears colorized in the Blizzard Addon list and management tools.

### Changed

- Refined Side Tab positioning for ElvUI users to ensure perfect alignment with the Social panel.

### Fixed

- Resolved "Ghost Frame" Issue: Fixed a bug where native WhoFrame components would linger on screen if the Social panel was closed via the Escape key while the Options tab was active.
- Database Sanitization: Enforced strict validation to prevent Level 0 (incomplete) player records from being saved, and added an automated cleanup to prune existing invalid records.
- UI Stability: Added comprehensive nil-safety to sorting and rendering logic to prevent interface crashes with partial data.

## [1.4.0] - 2026-04-28

### Added

- Database Browser: A new tab on the Social panel (Who frame) to browse and filter the historical player database.
- Last Seen Column: Support for relative timestamps (e.g., "5m ago") in the Who frame's second column.
- Options Dashboard: A dedicated side-tab for configuring data retention, proxy settings, and viewing database statistics.
- New Slash Commands: /whogui for UI access and /whofind for rapid chat-based database searching.
- Database Statistics: Real-time tracking of total players and faction breakdowns.
- Search Synchronization: Pressing Enter in the WhoFrame search box now triggers a background network query for new players.

### Changed

- Refactored /who override to use a unique internal tag for better compatibility with other addons.
- Improved chat links to use class coloring and interactive shift-click support.
- Silenced UI refreshes for world sightings (hovering) to prioritize performance; sightings are still recorded to the database in the background.
- Simplified chat output by removing redundant interactive links and simplifying network status tags.

### Fixed

- Resolved duplicate chat printouts for player queries.
- Fixed a bug where native WhoFrame components would occasionally "bleed" through the database browser overlay.
- Corrected scrollbar range issues in the database browser for lists exceeding 100 entries.
- Automated cleanup of temporary friends used for network proxy queries.

## [1.3.5] - 2026-04-20

- Added Passive Sighting: Automatically cache mouseover and target players.
- Implemented Channel Memory: The addon no longer forces WhorkComm channel hiding if manually changed.
- Added 'Sightings' to database statistics tracking.

## [1.3.4] - 2026-04-18

- Enforced live network requests for stale same-faction players (> 3 mins).
- Corrected 'Offline' fallback messages to 'Enemy detected' when appropriate.
- Refined guild and cache lookup priority logic.

## [1.3.3] - 2026-04-15

- Fixed Shift-Click mentions by restoring missing editbox detection logic.
- Improved ElvUI compatibility for chat hooks.

## [1.3.2] - 2026-04-10

- Switched to 'Request-First' approach for enemy queries.
- Implemented 'ResolveNetworkWait' to eliminate background chat spam.
- Baked versioning into the network protocol for better future-proofing.
- Optimized protocol with compacted faction data transmission.

## [1.3.1] - 2026-04-05

- Prioritized live requests over cache for enemies.
- Removed tentative language from output for more authoritative reporting.
- Implemented stale cache fallbacks with 'Last Seen' labels.

## [1.3.0] - 2026-04-01

- Major Update: Interactive Network Discovery.
- Implemented Gossip Protocol with Seniority Suppression.
- Added real-time network scanning UI feedback.
- Integrated ElvUI_Enhanced persistent data harvesting.
- Added case-insensitive @Name normalization.

## [1.2.2] - 2026-03-25

- Implemented case-insensitive name normalization.
- Added relative 'Last Seen' timestamps to database entries.
- Relaxed background query intervals for known enemies.

## [1.2.1] - 2026-03-20

- Integrated persistent cache harvesting from ElvUI_Enhanced.
- Implemented numeric ClassID translation logic for 3.3.5 standards.

## [1.1.2] - 2026-03-15

- Added output redirection logic (/whotab) to send results to specific frames.

## [1.1.1] - 2026-03-10

- Implemented state-aware friend list verification to prevent redundant system messages.

## [1.1] - 2026-03-05

- Protocol hardening and packet validation sanitization.
- Migrated from non-printable prefixes to standard WK: identifiers.

## [1.0] - 2026-03-01

- Initial release with background network query engine and basic chat integration.
