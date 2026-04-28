# Changelog

All notable changes to this project will be documented in this file.

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
