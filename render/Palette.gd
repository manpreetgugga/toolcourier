class_name Palette
extends RefCounted
## Single source of truth for every colour in Tiny Courier.
##
## The game looks like a soft clay diorama: warm, slightly saturated pastels
## under a dusk-tinted sky. Block shaders, props, packages and UI read from
## here so a palette tweak is a one-line change. All values are sRGB.

## Base albedo per block type.
const BLOCK: Dictionary = {
	&"stone": Color("#DCD3C6"),
	&"dark_stone": Color("#A3968C"),
	&"sand": Color("#F4DEAA"),
	&"grass": Color("#8CCB6E"),
	&"dirt": Color("#B98563"),
	&"wood": Color("#DDA066"),
	&"brick": Color("#E8845E"),
	&"water": Color("#6EC6EA"),
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

## Per-world look: background gradient, cloud sea, key light and ambient fill.
## "sky_top" is the top of the screen, "sky_horizon" the bottom of the screen;
## "sky_ground" is only used for the lower hemisphere of the ambient/radiance
## map. "clouds" is the coverage of the cloud sea below the diorama.
const THEMES: Dictionary = {
	&"meadow": {
		"sky_top": Color("#C9B8E8"),
		"sky_horizon": Color("#FDE3CF"),
		"sky_ground": Color("#E8CDBE"),
		"clouds": 0.55,
		"cloud_color": Color("#FFF3EC"),
		"sun_color": Color("#FFE1C2"),
		"sun_energy": 1.55,
		"ambient_color": Color("#B9AEE0"),
		"ambient_energy": 0.42,
		"shadow_blur": 3.0,
	},
	&"harbor": {
		"sky_top": Color("#9FC9E8"),
		"sky_horizon": Color("#FBEFDF"),
		"sky_ground": Color("#D3DDE0"),
		"clouds": 0.6,
		"cloud_color": Color("#FFFFFF"),
		"sun_color": Color("#FFF0DC"),
		"sun_energy": 1.5,
		"ambient_color": Color("#A9C6E6"),
		"ambient_energy": 0.45,
		"shadow_blur": 3.0,
	},
	&"old_town": {
		"sky_top": Color("#E3A7B4"),
		"sky_horizon": Color("#FCDDB8"),
		"sky_ground": Color("#E5C3AE"),
		"clouds": 0.5,
		"cloud_color": Color("#FFE9DD"),
		"sun_color": Color("#FFD8B0"),
		"sun_energy": 1.55,
		"ambient_color": Color("#C1AEDB"),
		"ambient_energy": 0.42,
		"shadow_blur": 3.0,
	},
}

const DEFAULT_THEME: StringName = &"meadow"


static func block_color(block_type: StringName) -> Color:
	return BLOCK.get(block_type, BLOCK[&"stone"])


static func theme(theme_name: StringName) -> Dictionary:
	return THEMES.get(theme_name, THEMES[DEFAULT_THEME])
