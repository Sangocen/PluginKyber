# KYBER Plugin Samples

Example Plugins for [KYBER](https://kyber.gg) (Star Wars Battlefront II multiplayer mod).

> [!WARNING]
> KYBER Plugins are still in development and may not work as expected. There is currently no official support or documentation for using plugins. Use at your own risk.

For deployment, API patterns, and conventions, see [`.cursor/rules/kyber-plugins.mdc`](.cursor/rules/kyber-plugins.mdc) and [`docs/lancer-serveur-avec-plugins.md`](docs/lancer-serveur-avec-plugins.md).

## Plugins overview

| Plugin | Description |
|--------|-------------|
| [AutoStart](AutoStart) | Automatically starts coop matches when at least one human player is present. |
| [BattlefieldCamera](BattlefieldCamera) | Client plugin: smooth camera move toward spawn (Battlefield-style). |
| [BotBalancer](BotBalancer) | Fills bot slots from gamemode capacity, shuffles/balances human teams on whitelisted PvP modes. |
| [BotDifficulty](BotDifficulty) | Sets and maintains bot AI difficulty (`AimNoiseScale`); chat command `/bd`. |
| [CoopTeamFix](CoopTeamFix) | Keeps human players on the correct coop faction; disables engine team balancing. |
| [DeployActionProbe](DeployActionProbe) | **Dev only:** chat `/probe` commands to find deploy-menu `actionId`s (hero slots). |
| [GunGame](GunGame) | Gun Game mode: progress through weapons on each kill. |
| [HVVPlaygroundPlugin](HVVPlaygroundPlugin) | Chat commands for voteban and team swap. |
| [OfficialServerTools](OfficialServerTools) | Utilities for official dedicated servers (HTTP, routes, shutdown). |

### Coop server stack

These plugins are commonly used together on **dedicated coop servers**:

| Plugin | Role |
|--------|------|
| **AutoStart** | Start the round without requiring 2+ human players. |
| **CoopTeamFix** | Put humans on the player faction, not the AI bot team. |
| **BotDifficulty** | Stable bot difficulty with in-game adjustment. |

**BotBalancer** targets **whitelisted PvP gamemodes** (Supremacy, etc.), not coop. Avoid running it alongside **CoopTeamFix** unless you understand the overlap (both touch team balancing).

---

## AutoStart

**Author:** Geeknasty

**Problem:** In coop, the server often requires **at least two human players** before `startgame` runs. A solo player can sit in the lobby indefinitely.

**Behavior:**

- On `Level:Loaded`, waits **30 seconds**, then runs `startgame` if there is **≥ 1 human player** (bots are ignored).
- If the level loads with no players, `ServerPlayer:Joined` starts the same **30 s** timer as a fallback.
- `HasStartedGame` prevents starting the same round twice.

**Summary:** Automatically starts coop with a single connected player, after a 30 s delay.

---

## BotBalancer

**Authors:** BattleDash, Magix

**Problem:** Empty slots on large PvP modes, and uneven human teams when players join mid-session.

**Behavior:**

1. **Bot count** — Every **5 s** (`Server:UpdatePre`), reads each gamemode’s `maxPlayers` from `ResourceManager:PartitionLoaded` (`GameModeInformationAsset`), targets **80%** of capacity (`desiredGameDensity = 0.8`), split **evenly per team**, and writes `forceFillGameplayBotsTeam1` / `forceFillGameplayBotsTeam2` under console settings **`AutoPlayers`**.

2. **Whitelisted gamemodes only** — Active only for:
   - `Mode1`
   - `PlanetaryBattles`
   - `IOISupremacyUnrestricted`  
   Otherwise bot fill is reset to 0.

3. **Human teams** — On load of a whitelisted mode: disables Kyber/Whiteshark auto team balance, **randomly shuffles** humans across team 1 and 2 (requires **≥ 2** humans), and on `Server:PlayerJoined` assigns newcomers to the smaller team.

**Summary:** Proportional bot backfill for listed PvP modes plus human team shuffle/balance—not intended for pure coop.

**Tunable constants** (in `BotBalancer/server/__init__.lua`): `updateIntervalSeconds`, `desiredGameDensity`, `whitelistedGameModes`, `playerBalancerTiedToWhitelistedGamemodes`.

---

## BotDifficulty

**Author:** Geeknasty

**Problem:** Bot difficulty (`AimNoiseScale` in **`AutoPlayers`**) may reset or drift; players need a stable default and a way to change it in-game.

**Behavior:**

- Default difficulty: **6 (Hard)** on scale **0 = Master … 12 = Easy**.
- On `Level:Loaded`: reapplies difficulty after **30 s** (no chat broadcast).
- Every **5 s**: silently reapplies the current value (guards against engine resets).
- Chat commands (message is cancelled so it does not appear in global chat):
  - `/bd`, `/botdiff`, `/botdifficulty`
  - Argument: number **0–12** or preset `master`, `knight`, `hard`, `medium`, `easy`
  - No argument: prints current difficulty and usage via `Kyber.Broadcast`

| Preset | Value |
|--------|-------|
| master | 0 |
| knight | 3 |
| hard | 6 (default) |
| medium | 9 |
| easy | 12 |

**Summary:** Sets and maintains bot AI difficulty; players adjust it with `/bd`.

---

## CoopTeamFix

**Author:** Geeknasty

**Problem:** In coop (`Mode9` = attack, `ModeDefend` = defend), the engine may **auto-balance humans onto the AI bot faction** instead of the intended player side.

**Behavior:**

- **`CoopAttackerTeams`** maps each known coop level path to the **attacking** faction (team 1 = Light Side, team 2 = Dark Side). In defend mode, the player team is the **opposite** of the attacker.
- When level + mode match:
  - Runs `Kyber.DisableTeamBalancing true` and `Whiteshark.AutoBalanceTeamsOnNeutral false`.
  - **15 s** after `Level:Loaded`: moves all humans to the correct team.
  - On `ServerPlayer:Joined`: correction after **5 s**.
  - On `ServerPlayer:Spawned`: immediate correction if team is wrong.

Supported coop modes: `Mode9` (attack), `ModeDefend` (defend). Maps are listed in `CoopTeamFix/Server/__init__.lua` (`CoopAttackerTeams`).

**Summary:** Forces humans onto the correct coop faction and blocks engine team balancing onto the bot side.

**Tunable delays** (in `CoopTeamFix/Server/__init__.lua`): `initialMoveDelay` (default 15 s), `joinMidMatchDelay` (default 5 s).

---

## Other plugins (brief)

### BattlefieldCamera

Client-side plugin (dev only; client plugin path is deprecated in production). Uses `ClientCameraManager:Push` for eased camera motion toward spawn.

### GunGame

Progression through a weapon list on each kill. Configurable via `KYBER_PLUGIN_SETTING_*` environment variables.

### HVVPlaygroundPlugin

Chat-based voteban and team swap for playground servers.

### OfficialServerTools

Minimal HTTP server via `SocketManager`, routing, and graceful shutdown helpers for official dedicated hosts.
