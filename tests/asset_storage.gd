extends SceneTree
const Assets = preload("res://addons/stg_maker/authoring/asset_store.gd")
const Session = preload("res://addons/stg_maker/ui/session.gd")
const Fixture = preload("res://tests/game_fixture.gd")
const GameDocument = preload("res://addons/stg_maker/authoring/game_document.gd")
var checks: int = 0
var failures: int = 0
var directory: String

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func run() -> void:
	directory = "user://asset_storage_%s" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	_test_library_roundtrip()
	_test_game_roundtrip()
	_test_drafts_and_guards()
	print("ASSET STORAGE RESULT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_library_roundtrip() -> void:
	var library = Fixture.create().library
	var behavior = STGBehaviorFlow.new()
	behavior.id = "stored_behavior"
	var wait = STGFlowNode.new(); wait.id = "wait"; wait.kind = "wait"; wait.delay = 0.5
	behavior.nodes.append(wait); behavior.entry_id = wait.id; library.behaviors.append(behavior)
	var original_title = library.levels[0].title
	var path = directory.path_join("library.tres")
	check(Assets.save_library(library, path).is_empty(), "split library saves")
	var index = FileAccess.get_file_as_string(path)
	check(index.contains("library.assets/levels/") and not index.contains("巡航试炼"), "index references external assets instead of embedding all content")
	check(library.levels[0].resource_path.is_empty() and library.levels[0].title == original_title, "saving does not mutate input snapshot paths or values")
	var session = Session.new()
	session.recovery_folder = directory.path_join("recovery")
	check(session.open(path).is_empty() and session.project.validate().is_empty(), "editor reopens split assets through normal project entry")
	check(session.project.behaviors.size() == 1 and index.contains("library.assets/behaviors/") and ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE).behaviors[0].resource_path.contains("library.assets/behaviors/"), "reusable behavior is stored and reopened as an independent asset")
	check(session.project.behaviors[0].nodes[0].delay == 0.5, "independent behavior retains precise delay configuration")
	var disk_index: STGProject = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var asset_path: String = disk_index.levels[0].resource_path
	check(not asset_path.is_empty() and not asset_path.contains("::"), "each level is an independent resource file")
	var revision = Assets.capture(path)
	check(revision.size() > 4 and revision.has(ProjectSettings.globalize_path(asset_path).replace("\\", "/")), "disk revision includes external asset files")
	var before = FileAccess.get_sha256(asset_path)
	check(session.save(path).is_empty(), "unchanged split project can be saved again")
	check(FileAccess.get_sha256(asset_path) == before, "unchanged asset serializes deterministically")
	session.edit(func(next): next.levels[0].title = "edited independently")
	check(session.save(path).is_empty(), "changed asset saves through normal undo session")
	check(FileAccess.get_sha256(asset_path) != before, "only intended level data changes")
	var cached = ResourceLoader.load(asset_path)
	cached.title = "unsaved cached value"
	check(session.open(path).is_empty() and session.project.levels[0].title == "edited independently", "reopening refreshes external asset data without reloading scripts")
	write(asset_path, FileAccess.get_file_as_string(asset_path).replace("edited independently", "external edit"))
	session.edit(func(next): next.levels[0].title = "editor conflict")
	check(not session.save(path).is_empty(), "external edits block stale overwrite")
	check(FileAccess.get_file_as_string(asset_path).contains("external edit"), "conflicting save preserves externally edited file")
	check(session.open(path).is_empty() and session.project.levels[0].title == "external edit", "reopen adopts external file as the new baseline")
	session.edit(func(next): next.levels[0].title = "merged result")
	check(session.save(path).is_empty(), "merged edits save after reopening")
	check(library.levels[0].title == original_title, "all saves leave original fixture untouched")

func _test_game_roundtrip() -> void:
	var game = Fixture.create()
	var path = directory.path_join("game.tres")
	var library_path = directory.path_join("game_library.tres")
	check(not Assets.save_game(game, path, path).is_empty(), "game and library cannot overwrite the same index")
	check(Assets.save_game(game, path, library_path).is_empty(), "game and library save in one transaction")
	var loaded = GameDocument.load_definition(path)
	check(loaded != null and loaded.validate().is_empty(), "saved game reloads with valid references")
	check(loaded.player.resource_path.ends_with("game.assets/players/main.tres") and loaded.world.resource_path.ends_with("game.assets/worlds/main.tres"), "player and world are standalone assets")
	check(loaded.library.resource_path == library_path, "game index retains independent battle library reference")
	var revision = Assets.capture(path)
	var player_path: String = loaded.player.resource_path
	write(player_path, FileAccess.get_file_as_string(player_path) + "\n; external change\n")
	check(not Assets.save_game(game, path, library_path, revision).is_empty(), "player asset conflicts protect the entire game transaction")
	loaded = GameDocument.load_definition(path)
	loaded.player.move_speed = 300
	check(Assets.save_game(loaded, path, library_path, Assets.capture(path)).is_empty(), "reloaded game adopts external revisions safely")
	check(is_equal_approx(GameDocument.load_definition(path).player.move_speed, 300), "game reload sees changed external player configuration")

func _test_drafts_and_guards() -> void:
	var library = Fixture.create().library
	var null_index = library.bullets.size()
	library.bullets.append(null)
	library.bullets[0].id = "../unsafe\\id"
	library.bullets.append(library.bullets[0])
	var path = directory.path_join("draft.tres")
	check(Assets.save_library(library, path).is_empty(), "invalid IDs, duplicate IDs and null items can be preserved as drafts")
	var session = Session.new()
	check(session.open(path).is_empty() and session.project.bullets.size() == null_index + 2 and session.project.bullets[null_index] == null, "draft roundtrip retains unfinished content")
	var marker_path = path.get_basename() + ".assets/" + Assets.MARKER
	var marker = JSON.parse_string(FileAccess.get_file_as_string(marker_path))
	check(marker.files.keys().all(func(relative): return Assets._safe_relative(relative)), "asset file names cannot escape the selected directory")
	var old_index = FileAccess.get_sha256(path)
	marker.files["../outside.tres"] = "forged"
	write(marker_path, JSON.stringify(marker))
	check(not Assets.save_library(library, path).is_empty() and FileAccess.get_sha256(path) == old_index, "forged asset marker is rejected before writing")
	var clean = Fixture.create().library
	var blocked = directory.path_join("blocked.tres")
	DirAccess.make_dir_recursive_absolute(blocked)
	check(not Assets.save_library(clean, blocked).is_empty(), "directory at index path forces commit failure")
	var asset_directory = blocked.get_basename() + ".assets"
	var folder = DirAccess.open(asset_directory)
	check(folder == null or folder.get_files().is_empty(), "failed index commit rolls back created marker and files")
