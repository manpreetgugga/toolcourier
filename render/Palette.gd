class_name Palette
extends RefCounted
## Single source of truth for every colour in Tiny Courier.
##
## All values are sRGB hex taken from the art bible. Block shaders, props,
## packages and UI read from here so a palette tweak is a one-line change.

## Base albedo per block type.
const BLOCK: Dictionary = {
	&"stone": Color("#B9B4AA"),
	&"dark_stone": Color("#7E7A74"),
	&"sand": Color("#E3CFA1"),
	&"grass": Color("#8DB36B"),
	&"dirt": Color("#A57D5A"),
	&"wood": Color("#B9814F"),
	&"brick": Color("#C86B4A"),
	&"water": Color("#5FA8C9"),
}

## The single accent used by every interactive part.
const ACCENT: Color = Color("#F2A541")

## Package / delivery pad colours.
const PACKAGE: Dictionary = {
	&"red": Color("#E4572E"),
	&"green": Color("#4C9F70"),
	&"blue": Color("#3E7CB1"),
	&"yellow": Color("#F3C623"),
}

## Courier robot colours.
const COURIER_BODY: Color = Color("#F4EEDF")
const COURIER_VISOR: Color = Color("#2B2D42")
const COURIER_EYE: Color = Color("#5CE1E6")

## Per-world look: background gradient, key light and ambient fill.
## "sky_top" is the top of the screen, "sky_horizon" the bottom of the screen;
## "sky_ground" is only used for the lower hemisphere of the ambient/radiance map.
const THEMES: Dictionary = {
	&"meadow": {
		"sky_top": Color("#8FB8DE"),
		"sky_horizon": Color("#F5E6D3"),
		"sky_ground": Color("#C9C2B4"),
		"sun_color": Color("#FFF1DD"),
		"sun_energy": 1.3,
		"ambient_color": Color("#A9C3E0"),
		"ambient_energy": 0.55,
	},
	&"harbor": {
		"sky_top": Color("#79B4D4"),
		"sky_horizon": Color("#F2EEE2"),
		"sky_ground": Color("#B8C7C9"),
		"sun_color": Color("#FFF4E4"),
		"sun_energy": 1.3,
		"ambient_color": Color("#A4C8DE"),
		"ambient_energy": 0.58,
	},
	&"old_town": {
		"sky_top": Color("#C3A3C4"),
		"sky_horizon": Color("#F7D8B5"),
		"sky_ground": Color("#CDB39E"),
		"sun_color": Color("#FFE6C7"),
		"sun_energy": 1.35,
		"ambient_color": Color("#B7B4D6"),
		"ambient_energy": 0.52,
	},
}

const DEFAULT_THEME: StringName = &"meadow"


static func block_color(block_type: StringName) -> Color:
	return BLOCK.get(block_type, BLOCK[&"stone"])


static func theme(theme_name: StringName) -> Dictionary:
	return THEMES.get(theme_name, THEMES[DEFAULT_THEME])
