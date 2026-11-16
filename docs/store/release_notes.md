# Release notes

Play Console takes up to 500 characters per language, between the
language's tags; paste each block as it is.

## 1.2.2 (version code 6): production, the first public release

Version code 5 is taken, and Play never frees a used code. It went to a
rebuild of 1.2.1 that was uploaded to the library on 2026-11-16 and is in
no release.

Upload the bundle to the library (App bundle explorer → Upload new version),
then pick it with "Add from library" in the production release. It still
uses Google's test ad ids. The production notes are written for players
who are new to the game, so they introduce it rather than list changes:

```
<en-US>
Welcome to Tiny Courier, a calm clay puzzle game.
• 460 levels across seven worlds, from the Meadow to the Frost Peaks
• Slide bridges, ride lifts, open gates and bounce on springs to deliver every parcel
• A step-by-step walkthrough on the first level
• Every parcel and its pad share a symbol, for colour-blind players
• No timers and no lives: undo, restart, and a hint when you're stuck
</en-US>
```

The block after the change list is for a closed-testing release of 1.2.2,
if one is made.

Bump `version/code` to 6 and `version/name` to "1.2.2" in both presets of
`export_presets.cfg` (and `config/version` in `project.godot`) before
building it, and run `tools/prepare_android_build.ps1` before the export.
This release replaces 1.2.1 (version code 4), which it includes. Changes
since 1.2.0:

- Fixes for the two engine crashes in 1.2.0's Crashlytics, both in the
  Vulkan renderer (symbolized against Godot 4.7.1's debug symbols; see
  README, Safe mode): the SIGTRAP "Vulkan device was lost" on the Samsung
  SM-A715F, and the SIGSEGV at start-up when Vulkan could not be brought up
  (vivo V2253, a Samsung, Android 15). Those phones, and Qualcomm phones
  whose Vulkan driver is older than 1.3, start on OpenGL; any other phone
  where the game died while starting or on screen uses OpenGL from the next
  start (`core/SafeBoot.gd`).
- Back on the main menu now sends the game to the background, like the home
  button, instead of closing it, and the process ends without the engine's
  shutdown when Android closes the game.
- Crash reports carry the renderer and whether safe mode is on.
- Settings ends with the studio credit, the Kpstn Studios mark and "Made by
  Kpstn Studios" with the version.
- From the testers' report on 1.2.0:
  - The first level has a walkthrough, step by step, with the hint arrow
    showing where to tap and a Skip (`ui/Walkthrough.gd`).
  - Every parcel colour has a symbol on the parcel and its pad, for
    colour-blind players (`render/ParcelSymbol.gd`).
  - Settings has Rate us, and finishing a world for the first time asks for
    a rating on Google Play, twice at most (`core/Rating.gd`).
  - A fuller store description and captioned screenshots
    (`docs/store/listing.md`).

```
<en-US>
New: a walkthrough on the first level, with a Skip.
New: every parcel and its pad share a symbol, so colour-blind players can match them.
New: Rate us in Settings.
Fixes crashes on some Samsung and vivo phones.
Back on the main menu now puts the game in the background instead of closing it.
Settings now shows who makes the game: Kpstn Studios.
This build shows test ads from level 21 on.
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
