# AGENTS.md

Godot 4.7.2 / Forward+ / GDScript first-person horde shooter. The repo root is the
Godot project. `README.md` is the Russian design log for mechanics, enemies,
weapons, netcode, and asset history; trust it for intent, but its `D:\...` paths
are stale. This checkout uses `godot` on `PATH`.

## Commands

Run from the repo root:

```sh
godot --path .                                      # play from the main menu
godot --headless --path . --import                  # reimport after asset changes
godot --headless --path . --script res://tools/validate.gd
godot --headless --path . --script res://tools/test_waves.gd
godot --headless --path . --script res://tools/test_enemies.gd
godot --headless --path . --script res://tools/test_arena_settings.gd
godot --headless --path . --script res://tools/test_bhop.gd
godot --headless --path . --script res://tools/test_weapon_movement.gd
godot --headless --path . --script res://tools/test_weakpoint.gd
```

- `tools/*.gd` are `SceneTree` scripts launched with `--script`; they instantiate
  `res://scenes/main.tscn` directly. Check the exit code and the final
  `ALL CHECKS PASSED` where present.
- `validate.gd` only prints diagnostics, it is not an assertion suite.
- `tools/test_levelup.gd` and `tools/capture_*.gd` need a window (`godot --path .`),
  not `--headless`.
- Two-process co-op probe:

```sh
godot --headless --path . --script "$PWD/tools/online_probe.gd" -- host
godot --headless --path . --script "$PWD/tools/online_probe.gd" -- client
```

- Headless runs commonly print dummy-renderer errors such as `Parameter
  "material" is null`; judge by exit code and failed assertions, not by those.

## Architecture

- `scenes/main_menu.tscn` is the entry point. `scenes/main.tscn` is the arena.
- There are deliberately **no autoloads**. `Net` and `Settings` use static state
  so `--script` tools work without autoloads. Do not make gameplay code depend on
  autoloads.
- `Main` (`scripts/main.gd`) owns `WaveManager`, `LevelUpMenu`, `RunOver`,
  `NetworkGame`, HUD, and the player reference.
- `NetworkGame` always configures/spawns the local player, including offline. In
  offline mode the authored `Player` node is reused, which the tools rely on.
  Tests also use groups `player`, `enemies`, and `xp_gems`.
- Co-op is host-authoritative: the host runs waves, AI, and damage; clients send
  their own transform and receive enemy snapshots. Client enemies are
  `net_puppet` nodes without AI.
- `Weapon` (`scripts/weapons/weapon.gd`) does hitscan combat; headshots use each
  enemy's `head_zone_height` / `headshot_multiplier`. All tuning lives in
  `@export` properties.
- UI is mostly built in GDScript (menus, HUD, level-up cards), not authored as
  large node trees. Follow that pattern.
- Blender import is disabled in `project.godot`. Commit `.glb` runtime assets;
  `.blend`/`.fbx`/`.obj` are sources. `tools/blender_*.py` are headless `bpy`
  generators, and `.gdignore` hides raw/source folders from Godot.

## Repo gotchas

- The GodotSteam GDExtension is Windows x86_64 only. On Linux it prints
  `No GDExtension library found...` / `dynamic library not found`; Steam is
  unavailable. Do not treat those as new regressions.
- `build/` is ignored. `.godot/` is currently **not** ignored and appears as
  untracked; never stage it.
- Git LFS covers `*.png`, `*.jpg`, `*.jpeg`, `*.webp`, `*.wav`, `*.ogg`, `*.mp3`,
  `*.mp4`, `*.glb`, `*.gltf`, `*.fbx`, `*.blend`, `*.zip`, `*.pck`, and `*.exe`.
- Keep `.uid` and source-side `.import` files in normal Git. Do not hand-edit
  `.godot/` caches, imported scene internals, or generated import outputs.
- Do not add plugins, change the renderer/engine version, or rewrite history
  without explicit approval.

## Style

- GDScript: explicit types where practical, `snake_case` members/files,
  `PascalCase` `class_name`. Existing code uses `##` doc comments and
  `@export_group`.
- Use InputMap actions (`fire`, `aim`, `reload`, `weapon_1`...), never physical
  keys. Keep movement in `_physics_process`; use delta/timers for time behavior.
- Physics layers: 1 world, 2 player, 3 enemies, 4 props. Keep damage, health,
  collision masks, and death cleanup consistent across player/weapon/enemy.
- Put gameplay values in exported properties rather than scattered constants.
  Follow the existing signal/reference patterns instead of deep hard-coded paths.
- Verify combat changes with weapon origin/aim alignment, hit registration,
  cooldown, and feedback. Smoke-test the affected gameplay loop, not just the
  edited script.
- Use Godot MCP for editor/scene operations and Blender MCP only for 3D asset
  work. Save/close editor state before editing a scene on disk.

## Git and validation

- Validate each completed coherent change locally and commit it with a concise
  English imperative message (about 2–6 words).
- The LFS gate is mandatory for **every** commit, including docs. Stage explicit
  paths; never `git add .` or `git add -A` in a dirty tree. Run
  `git diff --cached --check`, `git lfs status`, and `git lfs fsck --objects`.
- For every staged LFS path, confirm the staged blob is a pointer and its object
  exists. A syntax check for one path:

```sh
git show ':path/to/asset.glb' | git lfs pointer --check --strict --stdin
```

- Never stage pre-existing user work, generated caches, builds, secrets, or
  private MCP configuration. Never push, force-push, or rewrite history without
  an explicit request.
- Report what was actually validated, including blocked checks or MCP gaps. Do
  not claim a commit, test, save, or upload that did not happen.
