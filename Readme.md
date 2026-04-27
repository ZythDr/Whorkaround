# Whorkaround

Whorkaround is a /who workaround addon for Project Epoch where the standard `/who` command is disabled. It provides an alternative for identifying players by gathering data from multiple sources and building a persistent, account-wide database of the players you encounter.

### Key Features

- **Authoritative /who**: Replaces the standard query with a fact-based reporting system. No more "likely" or "guessed" info—if a player is found, you get their exact Level, Class, and Faction.
- **High-Accuracy Gossip Protocol**: When you query an enemy or an offline player, Whorkaround scans the network. The protocol uses "Seniority Suppression," meaning the user with the **freshest** data replies first, instantly providing you with the most accurate location.
- **Self-Response System**: If you query a player who is also using Whorkaround, their addon will immediately auto-respond with 100% accurate information about themselves.
- **Offline & Cross-Faction Discovery**: Fully supports identifying opposing faction members and same-faction players who are currently offline by leveraging the community database.
- **Interactive Links & Tooltips**: Results feature clickable **(Live)** or **(Cached)** labels. Clicking these labels in chat provides a detailed breakdown of exactly where the data came from.
- **Smart Linking & Mentions**: Link any player in chat by typing `[Name]` or `@Name`. The addon automatically colorizes the name by class, normalizes capitalization, and creates a fully functional, clickable player hyperlink.
- **Persistent Database**: Automatically saves player data into an account-wide database with "Last Seen" timestamps so you can judge the age of the data at a glance.
- **Silent Operation**: All background queries and friends-list "handshakes" are handled quietly. Annoying system messages are suppressed, and the friends list is automatically kept clean.

### Commands

- `/who Name` or `/whom Name` - Performs a manual query for a player.
- `/whotab [TabName]` - Redirects all Whorkaround output to a specific chat tab.
- `/whostats` - Displays a breakdown of your database (Total players, Factions, Sources).
- `/whotoggle` - Toggles the automatic override of the standard `/who` command.
- `/whocleardb` - Wipes your local player database.
- `/whodebug` - Verifies your connection to the WhorkComm network.

### Compatibility

Designed specifically for Project Epoch. Fully compatible with ElvUI and ElvUI Enhanced, harvesting their internal caches to populate your database even faster.
