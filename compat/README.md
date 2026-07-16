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
- `Modules/Map.lua`'s `SafeResetWorldMapFrames()` (fired from the
  `WorldMapFrame` Show/Hide hooks) forces `WorldMapDetailFrame` scale back to
  `1.0`, scroll to `0`, and clears `zoomedIn`. This yanks the map back to
  un-zoomed on the next `Show` after a wheel-zoom, so **the map won't zoom —
  it snaps straight back to the previous zoom level.**

**Fix:** `lootcollector-magnify-standdown.patch` — apply to the LootCollector
folder. When `Leatrix_Maps` is loaded, two things stand down:

- the embedded Magnify (`Magnify/Main.lua`) stands down entirely and hands the
  shadowed `WorldMapScrollFrame` / `WorldMapScrollFrameScrollBar` globals back
  to Leatrix's frames (fixes the immovable window);
- `Map.lua`'s `SafeResetWorldMapFrames()` becomes a no-op (fixes the zoom
  snap-back).

Loot pins keep working in both cases: they anchor to `WorldMapDetailFrame`,
which Leatrix pans and zooms the same way.

**Re-apply after every LootCollector update** (the patch modifies
`LootCollector/Magnify/Main.lua` and `LootCollector/Modules/Map.lua` in
place), or PR it upstream. A LootCollector update overwrites both files and
the map goes back to being stuck.

Verified against LootCollector **beta 0.9.2** (upstream moved the addon into a
`LootCollector/` subfolder at that version; the patch paths match the new
layout). Apply with:

```bash
git apply lootcollector-magnify-standdown.patch     # from the repo root
```

or copy the two guards in by hand — they are one early-return each in
`Magnify.SetupWorldMapFrame` / `Map:SafeResetWorldMapFrames`, plus the
stand-down block in `Magnify.OnEvent`.

Without Leatrix Maps installed, LootCollector's behavior is unchanged.
