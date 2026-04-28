# Whorkaround

Whorkaround is a social intelligence suite for Project Epoch where the standard /who command is disabled. It provides a robust alternative for identifying players by gathering data from multiple sources and building a persistent, account-wide database of the players you encounter.

### Key Features

- **Database Browser**: Integrated directly into the Blizzard Social Panel. Access and filter your historical player database with real-time searching and sorting.
- **Authoritative Data**: Provides exact Level, Class, and Faction information. No more "guessed" data—if a player is found, the results are accurate.
- **High-Accuracy Network Protocol**: When you query an enemy or an offline player, Whorkaround scans the network. The protocol uses "Seniority Suppression," ensuring the fresher data always takes priority.
- **Self-Response System**: If you query a player who is also using Whorkaround, their addon will immediately auto-respond with 100% accurate, live information about themselves.
- **Offline & Cross-Faction Discovery**: Supports identifying opposing faction members and offline same-faction players by leveraging the community database.
- **Proxy Lookups**: Queries for enemy faction players automatically trigger community members on that side to perform live "Friends List" checks on your behalf.
- **Last Seen Tracking**: The database records relative timestamps (e.g., "5m ago"), allowing you to judge the age and reliability of data at a glance.
- **Options Dashboard**: A dedicated side-tab for managing data retention (1-4 weeks), configuring proxy settings, and viewing database statistics.
- **Smart Linking & Mentions**: Link any player in chat by typing [Name] or @Name. The addon colorizes the name by class, normalizes capitalization, and creates a functional player hyperlink.
- **Silent Operation**: All background queries and friends-list "handshakes" are handled quietly. System messages are suppressed, and the friends list is automatically managed to prevent clutter.

### Commands

- `/who Name` or `/whom Name` - Performs a manual query for a player.
- `/whogui` - Opens the Social panel directly to the Database Browser and Options.
- `/whofind Query` - Rapidly searches your local database for players matching the Name, Class, or Zone.
- `/whostats` - Displays a breakdown of your database totals and faction counts.
- `/whocleardb` - Wipes your local player database.
- `/whodebug` - Toggles technical logging and verifies network connection.

### Compatibility

Designed specifically for Project Epoch. Fully compatible with ElvUI and ElvUI Enhanced, harvesting their internal caches to populate your database even faster.
