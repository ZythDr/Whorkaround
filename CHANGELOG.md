# Changelog

All notable changes to this project will be documented in this file.

## [1.5.8] - 2026-05-13

### Changed

- **Emergency Purge Removed:** Removed the experimental `PLAYER_LOGOUT` emergency cleanup that attempted to purge temp friends at the exact millisecond of logging out, as this was suspected of causing client crashes. Normal cleanup upon logging back in handles this safely anyway.

## [1.5.7] - 2026-05-13

### Fixed

- **Friend Cleanup Reliability:** Completely rewrote the friends list management as a strict step-by-step handshake. Each phase (add → tag → read info → remove → confirm gone) now has to explicitly "give the go" to the next step, driven by server-confirmed `FRIENDLIST_UPDATE` events. `tempFriends` is now only ever cleared once the server confirms the player is no longer on your friends list — not speculatively. This should eliminate any remaining ghost friend scenarios.

## [1.5.6] - 2026-05-09

### Fixed

- **Ghost Friend Cleanup:** Temporary friends are now tracked in a local database, so if you log out or close the game before a query finishes, it should still clean them up on your next login. In case of a crash/disconnect, it should instead catch friends added by Whorkaround through a `Whorkaround:tag` note on any friends it adds.
- **Emergency Purge:** Whorkaround now instantly blocks all new queries if it sees a 20-second logout timer, and attempts to wipe all temporary friends right as the game closes.  
- **Chat Spam Fix:** Fixed an edge-case where aborted proxy queries (like when someone else answers the request first) would end up printing "removed from friends list" to chat.  
- **Nameplate Crash:** Fixed a rare crash when using third-party nameplate addons (like KuiNameplates) that could sometimes prevent the scanner from working.
