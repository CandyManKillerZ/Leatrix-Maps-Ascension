# Leatrix Maps (WoW 3.3.5a)

A feature-rich world map enhancement addon for World of Warcraft 3.3.5a,
backported from Leatrix Maps for WOTLK Classic



As a disclaimer this addon was about 90% vibecoded, but so far the result is better than expected and I wanted to share it. Feel free to report any issues.

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
