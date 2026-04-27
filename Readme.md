# Whorkaround

Whorkaround is a specialized utility for Project Epoch where the standard `/who` command is disabled. It provides a robust alternative for identifying players by gathering data from multiple sources and building a persistent, account-wide database of the players you encounter.

### Key Features

- **Replacement /who**: Replaces the standard `/who` command with a high-speed query system using the Friends List API to discover a player's level, class, and location.
- **Interactive Network Search**: When you query an unknown enemy player, Whorkaround performs a real-time "Gossip Search" across the network. It asks other online users for data, allowing you to identify opposing faction members who aren't on your own lists.
- **Gossip Protocol (Suppression)**: Uses an intelligent suppression algorithm to prevent network spam. When a data request is sent, only one user will typically respond, keeping the communication channel clean.
- **Smart Linking & Mentions**: Link any player in chat by typing `[Name]` or `@Name`. The addon automatically colorizes the name by class, normalizes capitalization, and creates a fully functional, clickable player hyperlink.
- **Persistent Database**: Automatically saves player data into a local, account-wide database. Includes "Last Seen" tracking so you know exactly how fresh the information is.
- **Data Harvesting**: Automatically populates your database by piggybacking off your Guild Roster, nearby players, and even ElvUI's internal class caches (including persistent data from *ElvUI Enhanced*).
- **Silent Operation**: All background queries and network activity are handled quietly. Annoying system messages like "Added to friends list" or "Joined channel" are suppressed to keep your chat log clean.

### Commands

- `/who Name` or `/whom Name` - Performs a manual query for a player.
- `/whotab [TabName]` - Redirects all Whorkaround output to a specific chat tab (e.g., `/whotab Queries`). Type without a name to reset to the default window.
- `/whostats` - Displays a breakdown of your database, including total players found and their sources (Guild, Manual, Network, etc.).
- `/whotoggle` - Toggles the automatic override of the standard `/who` command.
- `/whocleardb` - Wipes your local player database and starts fresh.
- `/whodebug` - Verifies your connection to the WhorkComm network and broadcasts your current version.

### Compatibility

Designed specifically for Project Epoch and the 3.3.5 client. It respects the Vanilla class/level caps and is fully compatible with ElvUI and ElvUI Enhanced.
