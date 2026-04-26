# Whorkaround

Whorkaround is `/who` workaround for Project Epoch where `/who` is disabled. It provides a way to identify players by gathering data from several different sources (Primarily Friends List) and building a persistent, account-wide database of the people you encounter.

### Features

- **Replacement /who**: Replaces the standard /who command with a custom query that uses the friends list to find a player's level, class, and location.
- **Persistent Database**: Automatically saves information about every player it finds into a local database that is shared across all your characters.
- **Smart Linking**: Allows you to link players in chat by simply typing their name in brackets, like `[Name]`. These links are class-colored and support standard left-click (whisper) and right-click (menu) behavior.
- **Data Harvesting**: Piggybacks off your guild roster, ElvUI's player cache (if present), and nearby players to populate your database without needing to run manual queries.
- **Crowdsourcing**: Shares information with other users of the addon through a hidden communication channel. This builds a shared knowledge base of the server's population in the background.
- **Faction Detection**: Automatically identifies when a player belongs to the enemy faction.
- **Silent Operation**: All background queries are handled quietly. System messages like "Added to friends list" are suppressed so they don't clutter your chat log.

### Commands

- `/who Name` or `/whom Name` - Performs a query for the specified player.
- `/whostats` - Displays a breakdown of your current database, including total players found and their sources.
- `/whotoggle` - Toggles the automatic `/who` override on or off.
- `/whocleardb` - Wipes your local player database and starts fresh.

### Compatibility

Designed specifically for Project Epoch and similar "Vanilla-plus" environments running on the 3.3.5 client. It respects the level 60 cap and only recognizes the original nine classes.
