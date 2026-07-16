# Leatrix Maps for Ascension WoW (3.3.5a)

A feature-rich world map enhancement addon for [Project Ascension](https://ascension.gg),
forked from the [3.3.5a backport](https://github.com/5Buttons/Leatrix-Maps-3.3.5) of Leatrix Maps for WOTLK Classic.

## Ascension-specific fixes in this fork

- **Custom zones render correctly** — zones without fog-reveal data (Ascension custom content) fall back to normal map rendering instead of appearing unexplored
- **Map window can be dragged** — left-drag anywhere on the map canvas (when not zoomed in) or the title bar moves the window; position persists across sessions
- **Quest objective glow follows the map** — the blue objective glow repaints correctly when the map window is moved or scaled (Ascension's client composites it over the UI, so it is also softened to keep the numbered quest icons readable)
- **No more stray quest panels** — the fullscreen quest-list layout (quest list and detail panels beside/below the map) is disabled; quest POIs on the map are unaffected
- **Map can never get stuck immovable** — if anything flips the map out of windowed mode (e.g. Ascension's quest-list auto-switch during dungeon quest updates), it is forced back to windowed on the next map open instead of silently disabling all dragging
- **Works alongside LootCollector automatically — no patching required** — LootCollector bundles its own copy of the Magnify zoom addon, which otherwise fights this one over the same map frames and leaves the map immovable and unzoomable. Leatrix Maps now detects it and takes ownership of the map on its own, so it keeps working across LootCollector updates. LootCollector's loot pins are unaffected

---
<img width="1919" height="1079" alt="image" src="https://github.com/user-attachments/assets/820f87a4-acbc-47be-b635-b696ed80e0ea" />

## Features

### Appearance
- Clean, borderless windowed map
- Thin border around the map canvas

### Map Opacity
- Configurable map opacity when stationary
- Fade when moving, with adjustable opacity (default: 50%)
  
### Map Controls
- **Unlock map frame** — drag any border to reposition the map anywhere on screen
- **Auto change zones** — map follows your character as you move between zones
- **Sticky map frame** — map stays open until you manually close it
- Reset map layout button to restore default position

### Elements
- Points of interest with a dedicated settings sub-panel
- Zone and dungeon level ranges with optional fishing level display
- Player and cursor coordinates displayed on the map
- Quest objectives overlay

### Zoom & Pan
- Scroll-wheel zoom with configurable maximum zoom level and zoom speed
- Click-and-drag panning across the map
- Optional persist zoom per zone — remembers your zoom level when reopening
- Coloured class icons for party and raid members (toggleable)
- These features were implemented from: https://github.com/rissole/Magnify-WotLK

### More
- **Show unexplored areas** — removes fog of war from all zone maps
- Zone map (battlefield minimap) visibility control — Never / Battlegrounds / Always
- ElvUI compatibility — backdrop suppression, dropdown skinning, mouse re-enable,
  and option locking when ElvUI's own worldmap module is active

---

## Commands

| Command | Description |
|---------|-------------|
| `/ltm`  | Open the Leatrix Maps settings panel |

---

## Installation

1. Download the addon and extract it.
2. Place the `Leatrix_Maps` folder into your `Interface/AddOns/` directory.
3. Restart the game or reload your UI (`/reload`).

---

## Credits

- **Leatrix** — original addon author
- Zoom adapted from [Magnify-WotLK](https://github.com/rissole/Magnify-WotLK)
