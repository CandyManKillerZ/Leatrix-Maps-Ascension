# Addon compatibility patches

## LootCollector (JollyggVersion) — embedded Magnify conflict

**Symptom:** map window cannot be moved; it snaps back to one spot on every
map open. Zoom/pan may also misbehave.

**Cause:** [LootCollector-JollyggVersion](https://github.com/gerob/LootCollector-JollyggVersion)
bundles its own copy of the Magnify zoom addon — the same addon
Leatrix_Maps_Zoom.lua is ported from. Both copies remodel the same Blizzard
map frames:

- Its `Frames.xml` creates a **second frame named `WorldMapScrollFrame`**,
  shadowing Leatrix's global — Leatrix's `PLAYER_ENTERING_WORLD` setup then
  wires the zoom system into the wrong frame.
- It `SetScript`s (replaces) `WorldMapButton` OnMouseDown/OnMouseUp/OnUpdate,
  killing Leatrix's canvas window-drag.
- Its OnShow wrapper runs `Magnify.SetupWorldMapFrame()` **after** Leatrix's
  position restore on every map open, re-anchoring `WorldMapFrame` to its own
  `WorldMapScreenAnchor` (default top-left) with its own scale.

**Fix:** `lootcollector-magnify-standdown.patch` — apply to the LootCollector
folder. When `Leatrix_Maps` is loaded, the embedded Magnify stands down
entirely and hands the shadowed `WorldMapScrollFrame` /
`WorldMapScrollFrameScrollBar` globals back to Leatrix's frames. Loot pins
keep working: they anchor to `WorldMapDetailFrame`, which Leatrix pans and
zooms the same way.

**Re-apply after every LootCollector update** (the patch modifies
`LootCollector/Magnify/Main.lua` in place), or PR it upstream.
