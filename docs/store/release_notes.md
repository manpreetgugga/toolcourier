# Release notes

Play Console takes up to 500 characters per language, between the
language's tags; paste each block as it is.

## 1.2.1 (version code 4): not uploaded yet

Bump `version/code` to 4 and `version/name` to "1.2.1" in both presets of
`export_presets.cfg` (and `config/version` in `project.godot`) before
building it, and run `tools/prepare_android_build.ps1` before the export.
Changes since 1.2.0:

- A fix for a crash at start-up on some Samsung phones with older Qualcomm
  graphics (Adreno 618): Qualcomm phones whose Vulkan driver is older than
  1.3 start on OpenGL, and any phone where the game died on screen uses
  OpenGL from the next start (`core/SafeBoot.gd`). Ported from Boomlets
  0.5.16; best-effort, not yet proven by Crashlytics.
- Back on the main menu now sends the game to the background, like the home
  button, instead of closing it, and the process ends without the engine's
  shutdown when Android closes the game.
- Crash reports carry the renderer and whether safe mode is on.
- Settings ends with the studio credit, the Kpstn Studios mark and "Made by
  Kpstn Studios" with the version.

```
<en-US>
Fixes a crash at start-up on some Samsung phones.
Back on the main menu now puts the game in the background instead of closing it.
Settings now shows who makes the game: Kpstn Studios.
This build shows test ads from level 21 on.
Please send private feedback on the Play page if a level feels stuck or looks wrong.
</en-US>
```

## 1.2.0 (version code 3): closed testing

Bump `version/code` to 3 and `version/name` to "1.2.0" in both presets of
`export_presets.cfg` (and `config/version` in `project.godot`) before
building it.

```
<en-US>
Frost Peaks is rebuilt as the final world.
• 50 new mountain levels over thin ice that cracks and breaks behind you
• Igloos, ice crystals, cable cars and a glowing evening sky
• Each world now opens with stars: hints help you collect them
• A grid of worlds, a spinning menu island and gentler zoom
Stars from the old Frost Peaks levels are reset.
This build shows test ads from level 21 on.
Please send private feedback on the Play page if a level feels stuck or looks wrong.
</en-US>
```

## 1.1.0 (version code 2): closed testing

Bump `version/code` to 2 and `version/name` to "1.1.0" in both presets of
`export_presets.cfg` before building it.

```
<en-US>
A much bigger Tiny Courier.
• 520 levels, with two new worlds: Blossom Valley, and Sunflower Fields with springs to bounce on
• Each world is a map of floating islands to explore
• Zoom further, pan with two fingers, and tap the courier to say hello
• A smoother first launch
• Daily reminders, and statistics and crash reports to fix bugs (turn either off in Settings)
This build shows test ads from level 21 on.
Please send private feedback on the Play page if a level feels stuck or looks wrong.
</en-US>
```

## 1.0.0 (version code 1): closed testing

```
<en-US>
The first test build of Tiny Courier.
• 50 calm puzzle levels across five worlds: Meadow, Harbour, Old Town, Orchard and Frost Peaks
• Undo, restart and hints, and up to three stars a level
• Graphics settings for older phones
From world 2 on, this build shows Google's test ads in place of real ones.
Please tell us about any level that feels stuck, anything that looks wrong, or a phone that runs slowly, with private feedback on the game's Play page.
</en-US>
```
