# DeployActionProbe

**Dev / playtest only.** Do not ship on public production servers.

Discovers `actionId` values for `ServerPlayer:SetInputEnabled` on the deploy screen (hero slots). See [docs/spec-deploy-action-probe.md](../docs/spec-deploy-action-probe.md) and [docs/methodologie-decouverte-actionid-deploiement.md](../docs/methodologie-decouverte-actionid-deploiement.md).

## Setup

1. Edit `PROBE_ADMINS` in `server/__init__.lua` (your in-game name).
2. Point KYBER at this folder:

```bash
KYBER_DEV_PLUGIN_PATH=E:\workspace\PluginExamples\DeployActionProbe
KYBER_LOG_LEVEL=debug
```

3. In-game (GA / Supremacy): `/probe help`

## Commands

| Command | Purpose |
|---------|---------|
| `/probe single <id> [name]` | Disable one action on one player |
| `/probe range <min> <max> [name]` | Disable a range (max 50 IDs) |
| `/probe enableone <id> [name]` | Re-enable one ID after a range sweep |
| `/probe auto on \| off` | Re-apply last single after death |
| `/probe off [name \| all]` | Restore known ID range |
| `/probe status` | Show current probe state |
