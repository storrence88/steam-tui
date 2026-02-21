# steam-tui

A terminal UI for browsing your Steam game library, organised by genre, with family sharing ownership info.

## Prerequisites

- Ruby 3.4+
- A [Steam API key](https://steamcommunity.com/dev/apikey)
- Your 64-bit Steam ID (e.g. `76561198xxxxxxxxx`)

## Installation

```bash
git clone https://github.com/storrence88/steam-tui
cd steam-tui
bundle install
```

## Configuration

Copy the example env file and fill in your credentials:

```bash
cp .example.env .env
```

Edit `.env`:

```
STEAM_API_KEY=your_key_here
STEAM_ID=76561198xxxxxxxxx
# FAMILY_STEAM_IDS=76561198...,76561198...   # Only if the family API returns 403
```

`FAMILY_STEAM_IDS` is an optional comma-separated list of Steam IDs. Use it as a fallback if the family group API returns a 403 (some accounts require an extra permission grant).

## Usage

```bash
bundle exec bin/steam-tui
```

The app fetches your library and family group on startup, then displays the interactive TUI.

## Keybindings

| Key | Action |
|-----|--------|
| `j` / `↓` | Move cursor down |
| `k` / `↑` | Move cursor up |
| `l` / `→` / `Enter` | Expand genre / select game |
| `h` / `←` | Collapse genre |
| `/` | Enter search mode |
| `Escape` | Exit search mode |
| `q` | Quit |

### Search mode

Type to filter games by name. Results use substring matching first, then subsequence (fzf-style) matching. The result count is shown in the search bar. Press `Enter` to select the highlighted result, or `Escape` to cancel.
