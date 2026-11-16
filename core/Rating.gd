class_name Rating
extends RefCounted
## Asking players to rate the game on Google Play (testers' report, 1.2.0):
## Settings has a Rate button, and the game asks once when a world is
## finished for the first time (see [method Hud.ask_rating]). A player who
## says Not now is asked again after a later world, at most
## [constant MAX_ASKS] times in all, and never once they have gone to rate.
## Everything is static; what was asked is kept in Settings.

const PACKAGE: String = "com.manpreetgugga.tinycourier"
## The game's page, in the Play Store app and on the web.
const MARKET_URL: String = "market://details?id=" + PACKAGE
const STORE_URL: String = "https://play.google.com/store/apps/details?id=" + PACKAGE
const MAX_ASKS: int = 2

## With [member dry_run] (tests) nothing opens; the pages that would have
## opened are listed in [member opened] instead.
static var dry_run: bool = false
static var opened: Array[String] = []


## Opens the game's page on Google Play (the Play Store app on Android, the
## web page elsewhere or when the app can't open), and stops the asking.
static func open_store() -> void:
	Settings.set_value(&"rated", true)
	if dry_run:
		opened.append(MARKET_URL if OS.get_name() == "Android" else STORE_URL)
		return
	if OS.get_name() == "Android" and OS.shell_open(MARKET_URL) == OK:
		return
	OS.shell_open(STORE_URL)


## Whether the game may ask now: never rated and asked fewer than
## [constant MAX_ASKS] times.
static func may_ask() -> bool:
	Settings.ensure_loaded()
	return not Settings.rated and Settings.rate_asks < MAX_ASKS


## Whether finishing [param level_path], when it had not been finished
## before, finished its whole world for the first time.
static func finishes_world(level_path: String, first_finish: bool) -> bool:
	if not first_finish:
		return false
	var world: int = LevelCatalog.world_of(level_path)
	var count: int = LevelCatalog.levels(world).size()
	return count > 0 and LevelCatalog.world_finished(world) == count


## Counts one ask.
static func asked() -> void:
	Settings.set_value(&"rate_asks", Settings.rate_asks + 1)
