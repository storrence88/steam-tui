# Plan: Steam Game Artwork in the Terminal

## Research Summary

### 1. Steam CDN — artwork URLs

Steam exposes artwork via a public CDN with **no authentication required**. The URL pattern is:

```
https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/{filename}
```

Useful assets (all JPEG):

| Asset | Filename | Dimensions | Aspect |
|---|---|---|---|
| Small capsule | `capsule_231x87.jpg` | 231 × 87 | 2.65 : 1 (landscape) |
| Header capsule | `header.jpg` | 460 × 215 | 2.14 : 1 (landscape) |
| Library capsule | `library_600x900.jpg` | 600 × 900 | 2 : 3 (portrait) |
| Library hero | `library_hero.jpg` | 3840 × 1240 | very wide |

**Best candidate for a detail pane:** `library_600x900.jpg` — portrait orientation fits
naturally in a vertical terminal column.  Fallback: `header.jpg` (almost every game has it).

Because the `appid` is already stored in `Game` (`models/game.rb:5`), no additional API
calls are needed — the URL is deterministic.

---

### 2. Terminal image rendering — options & trade-offs

`tty-image` **does not exist** in the TTY toolkit. The realistic options are:

#### Option A — `chafa` (recommended)
- A compiled CLI tool (`apt install chafa` / `brew install chafa`).
- Supports **Kitty graphics protocol**, **iTerm2 inline images**, **Sixel**, and **ANSI
  Unicode block art** as automatic fallbacks in that order.
- Called from Ruby via `` `chafa --size WxH --format kitty path/to/img.jpg` `` or via
  `Open3.popen3`.
- **No Ruby gem required**; works in xterm, Kitty, WezTerm, Ghostty, mlterm, VSCode
  terminal, and any Sixel-capable terminal; degrades gracefully to coloured block
  characters on everything else.

#### Option B — `imgcat` Ruby gem (v0.1.0, 2024)
- Pure-Ruby implementation of the **iTerm2 / WezTerm inline image protocol** (OSC 1337).
- Add `gem "imgcat"` — no compiled dependencies.
- Narrower terminal support: iTerm2, WezTerm, VSCode, mintty. No Sixel, no Kitty.
- Suitable if the project targets macOS-heavy users.

#### Option C — ANSI block art without system tools
- Gems like `catpix` convert images to 256-colour Unicode block characters using RMagick.
- Works everywhere but looks noticeably pixelated at small sizes; adds a heavy native
  dependency (ImageMagick).
- Not recommended given the alternatives.

**Recommendation: `chafa` for the widest compatibility, with `imgcat` as a pure-Ruby
fallback if `chafa` is absent.**

---

### 3. Will it actually render in the terminal?

**Yes, with caveats.**

| Terminal | Protocol | Result |
|---|---|---|
| Kitty | Kitty graphics | Crisp, full-colour |
| WezTerm | Kitty + iTerm2 | Crisp, full-colour |
| Ghostty | Kitty graphics | Crisp, full-colour |
| iTerm2 (macOS) | iTerm2 OSC | Crisp, full-colour |
| xterm (≥ 3.3) | Sixel | Good, 256-colour palette |
| foot | Sixel | Good |
| VSCode terminal | iTerm2 OSC | Good |
| tmux | Sixel passthrough (requires config) | Workable |
| plain xterm / GNOME Terminal | ANSI block art fallback | Readable, not pretty |

**Sizing:** a 20-column-wide image renders as roughly 10 character rows tall (terminal
cells are ~2× taller than wide). At right-pane widths of ~100 columns, the portrait
`library_600x900.jpg` scaled to 40 columns would occupy ~60 rows — more than enough for
a useful preview without overflowing a typical 24-row terminal.

**Frame-redraw concern:** the current TUI redraws the whole screen each frame using
`\e[H` + overwriting lines (`app.rb:267`). Inline image protocols embed the image data
inside the escape sequence stream, so they redraw correctly as long as cursor positioning
is respected. The image should be rendered as a block of lines in the detail pane, just
like text lines are today.

---

## Proposed Implementation Plan

### Step 1 — Artwork URL helper on `Game`

Add a `artwork_url` method to `models/game.rb`:

```ruby
def artwork_url
  "https://cdn.cloudflare.steamstatic.com/steam/apps/#{appid}/library_600x900.jpg"
end

def header_url
  "https://cdn.cloudflare.steamstatic.com/steam/apps/#{appid}/header.jpg"
end
```

### Step 2 — Artwork cache

Download artwork lazily and cache to disk in `~/.cache/steam-tui/{appid}.jpg` so repeated
selections don't re-download. A simple `ArtworkCache` service:

```ruby
# lib/steam_tui/services/artwork_cache.rb
module SteamTui
  module Services
    class ArtworkCache
      CACHE_DIR = File.expand_path("~/.cache/steam-tui")

      def fetch(game)
        FileUtils.mkdir_p(CACHE_DIR)
        path = File.join(CACHE_DIR, "#{game.appid}.jpg")
        unless File.exist?(path)
          resp = HTTParty.get(game.artwork_url, timeout: 10)
          File.binwrite(path, resp.body) if resp.success?
        end
        path if File.exist?(path)
      rescue StandardError
        nil  # artwork is optional; gracefully degrade
      end
    end
  end
end
```

Fetches should happen in a background `Thread` so the TUI remains responsive while the
image loads.

### Step 3 — Terminal capability detection

Detect at startup which renderer is available:

```ruby
# lib/steam_tui/services/image_renderer.rb
module SteamTui
  module Services
    class ImageRenderer
      def self.available?
        system("which chafa > /dev/null 2>&1") || defined?(Imgcat)
      end

      def render(path, width:, height:)
        if chafa?
          `chafa --size #{width}x#{height} --format auto "#{path}" 2>/dev/null`
        elsif imgcat?
          # imgcat gem returns the OSC escape sequence as a string
          Imgcat.encode(File.read(path, encoding: "binary"))
        end
      end

      private

      def chafa?   = system("which chafa > /dev/null 2>&1")
      def imgcat?  = defined?(Imgcat)
    end
  end
end
```

### Step 4 — Integrate into `DetailPane`

`detail_pane.rb` currently builds an array of text `lines`. Add artwork lines at the top
when an image is available:

```ruby
if image_lines
  lines.concat(image_lines)   # pre-rendered ANSI/escape lines from chafa
  lines << ""
end
```

Pass `image_lines` in from `App` (which owns the cache + renderer), keeping the pane
itself stateless.

### Step 5 — Async loading in `App`

When `@selected_game` changes, spawn a `Thread` to fetch + render the artwork and store
the result in `@artwork_lines`. Until the thread finishes, the detail pane shows a
`"  Loading artwork…"` placeholder line.

### Step 6 — Gemfile change (optional `imgcat` fallback)

```ruby
gem "imgcat", require: false   # optional; only used if chafa is absent
```

Guarded with `require: false` so the app still runs without it.

---

## Open questions / risks

1. **Not all games have `library_600x900.jpg`** — older titles may only have `header.jpg`
   or neither. The cache service should fall back: portrait → header → nil → no artwork
   shown.

2. **tmux** breaks most inline image protocols by default. Users running inside tmux will
   silently see no artwork unless they configure `tmux set -g allow-passthrough on`.

3. **Image width in character cells** must be calculated from the *actual* terminal cell
   pixel dimensions to avoid stretching. `chafa` handles this automatically. Without it,
   a safe default of half the pane width (in columns) is a reasonable starting point.

4. **Cache size** — a user with 500 games who browses every game will accumulate ~300 MB
   of artwork. A simple LRU cap (e.g. 200 entries, evict oldest) should be added to the
   cache service.
