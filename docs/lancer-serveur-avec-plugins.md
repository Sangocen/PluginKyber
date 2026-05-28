# Lancer un serveur KYBER avec des plugins Lua

Ce guide décrit comment charger les plugins de ce dépôt ([PluginExamples](../README.md)) selon le mode d’hébergement : **serveur dédié Docker**, **Kyber CLI** (dédié ou non), ou **KYBER Launcher**.

> **Avertissement** — Les plugins KYBER sont encore en développement. Il n’y a pas de support officiel dédié. Voir [la doc hébergement KYBER](https://docs.kyber.gg/g/hosting/dedicated-servers/config).

## Prérequis communs

- Une installation de **Star Wars Battlefront II** (licence EA / Maxima).
- Le **module KYBER** (`Kyber.dll`) compatible avec ta version du Launcher / CLI.
- Un **token API KYBER** (CLI : `kyber_cli` login, ou variable d’environnement).
- Pour l’hébergement en ligne : identifiants EA (`persona:password`) ou session déjà établie via le CLI.

Les plugins de ce repo sont des dossiers avec :

```
MonPlugin/
  plugin.json
  common/          # optionnel
  server/__init__.lua
  client/          # optionnel (plugins client peu supportés en prod)
```

---

## 1. Préparer les plugins

### Développement : dossier source

Pour itérer sur un plugin sans rebuild à chaque fois, pointe vers le dossier du plugin :

```powershell
$env:KYBER_DEV_PLUGIN_PATH = "E:\workspace\PluginExamples\GunGame"
```

Un seul plugin à la fois avec cette variable. Le moteur charge `common/__init__.lua` puis `server/__init__.lua`.

### Production : fichier `.kbplugin`

En production (Docker, dossier de plugins), chaque plugin doit être un **ZIP** nommé `NomDuPlugin.kbplugin` :

```powershell
cd E:\workspace\PluginExamples\GunGame
Compress-Archive -Path * -DestinationPath ..\GunGame.zip -Force
Rename-Item ..\GunGame.zip ..\GunGame.kbplugin
```

Place tous les `.kbplugin` dans un même dossier, par exemple `E:\kyber\plugins\`.

Le CI de ce repo fait la même chose sous Linux (`zip -r`) — voir [`.github/workflows/upload.yaml`](../.github/workflows/upload.yaml).

### Variables d’environnement (chargement)

| Variable | Usage |
|----------|--------|
| `KYBER_SERVER_PLUGINS_PATH` | Dossier contenant un ou plusieurs fichiers `*.kbplugin` (recommandé prod / CLI / Docker). |
| `KYBER_DEV_PLUGIN_PATH` | Chemin vers **un** dossier plugin **ou** un fichier `.kbplugin` (dev). |
| `KYBER_LOG_LEVEL` | `trace`, `debug`, `info` — utile pour vérifier le chargement. |
| `KYBER_DEV_MODE` | Active les logs de debug dans certains plugins d’exemple. |

Le Launcher **ne définit pas** ces variables tout seul : il faut les configurer toi-même (voir section Launcher).

---

## 2. Serveur dédié (Docker) — production

C’est le mode recommandé pour un serveur public 24/7. Doc officielle : [Configure and run your server](https://docs.kyber.gg/g/hosting/dedicated-servers/config).

### Structure sur l’hôte

```text
/mnt/battlefront/
  plugins/
    GunGame.kbplugin
    BotBalancer.kbplugin
  mods/          # optionnel (collections KYBER)
```

### Exemple `docker run`

Remplace les valeurs `<…>` par les tiennes :

```bash
docker run \
  -e MAXIMA_CREDENTIALS=<email>:<password> \
  -e KYBER_TOKEN=<token> \
  -e KYBER_SERVER_NAME=<nom-serveur> \
  -e KYBER_MAP_ROTATION=<rotation-base64> \
  -e KYBER_SERVER_PLUGINS_PATH=/mnt/battlefront/plugins \
  -v "<chemin-install-BF2>:/mnt/battlefront" \
  -v "<chemin-plugins-hôte>:/mnt/battlefront/plugins" \
  -it \
  ghcr.io/armchairdevelopers/kyber-server:latest
```

Les plugins du dossier monté sont détectés au démarrage du conteneur.

### Vérification

- Logs du conteneur : messages du type `[Plugin] Initializing script manager` et `[NomDuPlugin] Initialized plugin`.
- En jeu : comportement du mode (ex. Gun Game après démarrage de partie).

---

## 3. Kyber CLI — serveur dédié (local, sans Docker)

Le CLI lance le **jeu complet** avec `Kyber.dll`, en mode dédié (`KYBER_DEDICATED_SERVER` défini par défaut).

Sans Docker, il faut le bypass documenté dans les sources :

```powershell
$env:KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING = "1"
```

### Installation du CLI

- Archive Windows : `https://s3.kyber.gg/releases/stable/kyber-cli-win64.zip`
- Ou compilation depuis `E:\workspace\Kyber_w_lan` — voir [`docs/BUILD_CLI.md`](../../Kyber_w_lan/docs/BUILD_CLI.md) dans le dépôt Kyber.

### Exemple : dédié + un plugin (dev)

```powershell
$env:KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING = "1"
$env:KYBER_DEV_PLUGIN_PATH = "E:\workspace\PluginExamples\BotBalancer"
$env:KYBER_LOG_LEVEL = "debug"

kyber_cli start_server `
  --token "<ton-token-kyber>" `
  --server-name "Test Plugins" `
  --credentials "<persona>:<mot-de-passe-ea>" `
  --collection-file "C:\chemin\vers\ma-collection.kbcollection" `
  --collection-mods-directory "C:\chemin\vers\mods"
```

### Exemple : dédié + plusieurs plugins (`.kbplugin`)

```powershell
$env:KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING = "1"
$env:KYBER_SERVER_PLUGINS_PATH = "E:\kyber\plugins"
# Contenu du dossier : GunGame.kbplugin, BotBalancer.kbplugin, ...

kyber_cli start_server `
  --token "<ton-token-kyber>" `
  -n "Serveur Dev" `
  -c "<persona>:<password>" `
  --mod-folder "C:\chemin\vers\dossier-avec-kbcollection-et-mods"
```

### Options utiles

| Option | Description |
|--------|-------------|
| `--show-console` | Affiche la console KYBER. |
| `--lan` | Serveur LAN uniquement (pas d’enregistrement API). |
| `--rotation-file` | Fichier rotation `mode;map` par ligne. |
| `--startup-commands` | Fichier de commandes console au chargement. |
| `--module-path` | Dossier contenant `Kyber.dll` custom. |

Variables d’environnement alternatives au CLI : `KYBER_SERVER_NAME`, `KYBER_MAP_ROTATION` (base64), `KYBER_MOD_FOLDER`, `KYBER_SERVER_PASSWORD`, etc.

---

## 4. Kyber CLI — serveur non dédié (`--no-dedicated`)

Même commande `start_server`, mais mode **hébergeur** (équivalent « Host » du Launcher) : tu peux jouer dans la même instance, hooks client + serveur, pas le flag moteur « 24/7 ».

```powershell
$env:KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING = "1"
$env:KYBER_DEV_PLUGIN_PATH = "E:\workspace\PluginExamples\HVVPlaygroundPlugin"
$env:KYBER_LOG_LEVEL = "debug"

kyber_cli start_server --no-dedicated `
  --token "<ton-token-kyber>" `
  -n "Host Test" `
  -c "<persona>:<password>" `
  --map "S5_1/Levels/MP/Geonosis_01/Geonosis_01" `
  --mode "HeroesVersusVillains"
```

Avec `--no-dedicated`, le CLI **supprime** `KYBER_DEDICATED_SERVER` (le module ne considère plus la session comme serveur dédié pur).

**Plugins** : même mécanisme (`KYBER_DEV_PLUGIN_PATH` ou `KYBER_SERVER_PLUGINS_PATH`) — le mode dédié / non dédié ne change pas le chargement Lua côté serveur.

### LAN + plugins

```powershell
$env:KYBER_SERVER_PLUGINS_PATH = "E:\kyber\plugins"

kyber_cli start_server --no-dedicated --lan `
  --server-port 25200 `
  -n "LAN Plugins" `
  --token "<token>" `
  -c "<persona>:<password>" `
  --mod-folder "C:\chemin\mod-folder"
```

Découverte LAN : beacon UDP port `25201` (voir `Kyber_w_lan/docs/LAN.md`).

---

## 5. KYBER Launcher (onglet Host)

L’onglet **Host** démarre un serveur **non dédié** dans le processus du jeu. Le Launcher **n’expose pas** encore de champ « dossier plugins » dans l’UI : il faut passer par les **variables d’environnement** héritées par le jeu.

### Méthode recommandée (Windows)

1. **Préparer** les plugins (dossier dev ou `.kbplugin` dans un dossier).
2. Ouvrir **PowerShell** et définir les variables **avant** de lancer le Launcher depuis cette même fenêtre :

```powershell
$env:KYBER_DEV_PLUGIN_PATH = "E:\workspace\PluginExamples\GunGame"
$env:KYBER_LOG_LEVEL = "debug"
# Optionnel : plusieurs plugins en prod locale
# $env:KYBER_SERVER_PLUGINS_PATH = "E:\kyber\plugins"

& "C:\chemin\vers\Kyber Launcher.exe"
```

3. Dans le Launcher : onglet **Host** → configurer nom, rotation, mods → démarrer l’hébergement.

Le processus enfant (jeu + `Kyber.dll`) hérite des variables définies dans la session PowerShell parente.

### Variables système (persistantes)

Pour ne pas refaire l’étape à chaque fois (dev machine) :

```powershell
[System.Environment]::SetEnvironmentVariable(
  "KYBER_DEV_PLUGIN_PATH",
  "E:\workspace\PluginExamples\GunGame",
  "User"
)
```

Redémarrer le Launcher après modification.

### Limites Launcher

- Pas de chargement automatique des `.kbplugin` sans `KYBER_SERVER_PLUGINS_PATH` / `KYBER_DEV_PLUGIN_PATH`.
- Les plugins **client** (`client/__init__.lua`, ex. `BattlefieldCamera`) ne sont **pas** chargés via `KYBER_DEV_PLUGIN_PATH` (seul le realm **serveur** est utilisé pour ce chemin).
- Le `PluginManager` du Launcher (`BetterSabersPlugin.dll`, etc.) concerne des **mods client natifs**, pas les plugins Lua de ce repo.

---

## 6. Récapitulatif

| Méthode | Mode | Variable(s) plugins | Usage typique |
|---------|------|---------------------|---------------|
| **Docker dédié** | Dédié 24/7 | `KYBER_SERVER_PLUGINS_PATH` + volume | Production, serveur public |
| **CLI `start_server`** | Dédié (défaut) | `KYBER_*_PLUGIN*` + bypass Docker | Dev / test dédié local |
| **CLI `start_server --no-dedicated`** | Hébergeur | Idem | Dev en jouant, proche du Launcher |
| **Launcher Host** | Hébergeur | Env. **avant** lancement du Launcher | Test rapide à la maison |

---

## 7. Vérifier que les plugins sont actifs

1. **Logs** — Chercher :
   - `[Plugin] Initializing script manager`
   - `[NomDuPlugin] Initialized plugin`
   - Erreurs `Failed to load ... plugin.json`
2. **Niveau de log** — `$env:KYBER_LOG_LEVEL = "debug"`.
3. **Comportement en jeu** — Ex. Gun Game change les armes à chaque kill ; BotBalancer ajuste les bots après `Server:Init`.
4. **Un seul plugin en dev** — `KYBER_DEV_PLUGIN_PATH` ne charge qu’**un** plugin à la fois ; pour plusieurs, utiliser `KYBER_SERVER_PLUGINS_PATH` + fichiers `.kbplugin`.

### Dépannage rapide

| Problème | Piste |
|----------|--------|
| Aucun message plugin au démarrage | Variable non définie ou Launcher lancé hors de la session où tu as fait `$env:...` |
| `Skipping non-plugin file` | Le dossier ne contient que des `.kbplugin` (pas de sous-dossiers nus) pour `KYBER_SERVER_PLUGINS_PATH` |
| Erreur Lua au chargement | Voir la console / log ; corriger `server/__init__.lua` |
| Plugin GunGame sans liste d’armes | Variables `KYBER_PLUGIN_SETTING_*` (voir `GunGame/server/__init__.lua`) |

---

## 8. Paramètres optionnels (exemple GunGame)

Certains plugins lisent des variables au démarrage :

| Variable | Plugin | Description |
|----------|--------|-------------|
| `KYBER_PLUGIN_SETTING_GUNLIST` | GunGame | Liste d’armes (base64). |
| `KYBER_PLUGIN_SETTING_GUNCOUNT` | GunGame | Nombre d’armes dans la progression. |
| `KYBER_PLUGIN_SETTING_USE_BFPLUS_GUNLIST` | GunGame | Utiliser la liste BF+. |
| `KYBER_PLUGIN_SETTING_DISABLE_INPUT_BLOCK` | GunGame | Désactive le blocage d’inputs. |

---

## Liens

- [Doc serveur dédié KYBER](https://docs.kyber.gg/g/hosting/dedicated-servers/config)
- [README PluginExamples](../README.md)
- Sources moteur (events, chargement) : `E:\workspace\Kyber_w_lan\Module\Source\Script\ScriptManager.cpp`
- Build CLI : `E:\workspace\Kyber_w_lan\docs\BUILD_CLI.md`
- LAN : `E:\workspace\Kyber_w_lan\docs\LAN.md`
