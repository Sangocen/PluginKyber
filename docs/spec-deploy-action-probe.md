# Spécification v0.1 — Plugin sonde `DeployActionProbe`

> **Statut :** spécification de conception — outil **dev / playtest** uniquement.  
> **But :** identifier les `actionId` KYBER (`SetInputEnabled`) des **slots héros** au menu de déploiement.  
> **Consommateur :** [spec-battlepoint-equilibrage.md](./spec-battlepoint-equilibrage.md) §4.3.3 (cooldown héros 120 s).  
> **Procédure playtest :** [methodologie-decouverte-actionid-deploiement.md](./methodologie-decouverte-actionid-deploiement.md).

---

## 1. Objectifs

### 1.1 Problème

`ServerPlayer:SetInputEnabled(actionId, enabled)` agit sur une **action** du menu de déploiement (entier opaque côté Lua). Les IDs connus dans ce dépôt (`871087120`, `871087121`, `871087126` dans `GunGame/server/input_blocks.lua`) ciblent des **colonnes de classes**, pas les **slots héros**. Sans les bons IDs, le cooldown héros du `BattlepointBalancer` ne peut pas bloquer uniquement l’achat héros.

### 1.2 Livrable attendu

Un tableau validé en jeu, par exemple :

| actionId | Effet observé | Mode / map testés | Date |
|----------|---------------|-------------------|------|
| `871087???` | Slot héros non sélectionnable | GA, … | … |

À recopier ensuite en constantes dans le plugin d’équilibrage.

### 1.3 Hors scope

- Serveur public / production (risque de bloquer le déploiement par erreur).
- Détection automatique « cet ID = héros » sans observation humaine.
- Modes à UI de déploiement atypique en v0.1 : HVV, Hero Showdown, Co-op (priorité **GA / Supremacy**).
- Client plugins (API serveur uniquement).

---

## 2. Architecture

```
DeployActionProbe/
  plugin.json
  common/
    timer.lua          # copie depuis un exemple du dépôt (SetTimeout)
  server/
    __init__.lua       # logique sonde
```

| Fichier | Rôle |
|---------|------|
| `plugin.json` | `{ "name": "DeployActionProbe", "author": "…" }` |
| `server/__init__.lua` | Commandes, état par joueur, `SetInputEnabled`, logs |

**Chargement dev :**

```bash
KYBER_DEV_PLUGIN_PATH=E:\workspace\PluginExamples\DeployActionProbe
KYBER_LOG_LEVEL=debug
```

Ne pas déployer en `.kbplugin` sur un serveur public sans retirer le plugin après les tests.

---

## 3. API KYBER utilisée

| API | Usage |
|-----|--------|
| `PlayerManager.GetPlayers()` / `GetPlayer(name)` | Cibler le testeur |
| `player:SetInputEnabled(actionId, enabled)` | Désactiver / réactiver une action |
| `EventManager.Listen("ServerPlayer:SendMessage", …)` | Commandes chat (pattern `HVVPlaygroundPlugin`) |
| `EventManager.Listen("ServerPlayer:Killed", …)` | Option : lancer une sonde après mort → écran déploiement |
| `EventManager.Listen("ServerPlayer:Disconnect", …)` | **Réactiver tous les inputs** (sécurité) |
| `EventManager.Listen("ServerPlayer:Spawned", …)` | Réactiver après spawn si test en cours |
| `require "common/timer".SetTimeout` | Délai avant sonde post-mort (ex. 1,5 s) |
| `print` / logs | Traces `[DeployActionProbe]` |

Référence IDs classes (non héros) : `GunGame/server/input_blocks.lua`.

---

## 4. Modes de fonctionnement

### 4.1 Mode **single** (défaut recommandé)

Désactive **un seul** `actionId` sur **un seul** joueur, laisse les autres intacts.

```
/probe single <actionId>          # soi-même (émetteur du message)
/probe single <actionId> <pseudo> # admin : autre joueur
```

Comportement :

1. Mémoriser `actionId` et cible.
2. `SetInputEnabled(actionId, false)` sur la cible.
3. Log + message chat : « Probe : disabled &lt;id&gt; — testez héros / classes / véhicule ».
4. Ne pas désactiver d’autres IDs tant qu’un `/probe off` ou `/probe single` suivant n’est pas envoyé.

### 4.2 Mode **range** (balayage rapide)

Désactive toute une plage pour **un** joueur.

```
/probe range <debut> <fin>        # ex. /probe range 871087115 871087135
```

Comportement :

1. Pour chaque entier `id` de `debut` à `fin`, `SetInputEnabled(id, false)`.
2. Log la plage ; message chat invitant à noter ce qui est bloqué.
3. Utiliser ensuite `/probe enableone <id>` (§4.4) ou `/probe off` pour affiner.

**Attention :** peut rendre tout le déploiement inutilisable — réservé au serveur de dev isolé.

### 4.3 Mode **auto** (optionnel)

Au `ServerPlayer:Killed` du joueur marqué « testeur actif », après `PROBE_DELAY_SEC` (défaut **1,5 s**), appliquer le dernier mode **single** enregistré (réappliquer le même `actionId`).

Utile pour enchaîner les essais sans retaper la commande à chaque mort.

```
/probe auto on | off
```

### 4.4 Mode **enableone** (affinage après range)

Réactive **un seul** ID dans la plage précédemment désactivée (les autres restent à `false`).

```
/probe enableone <actionId>
```

Le testeur vérifie si le **slot héros** redevient sélectionnable → cet ID est un candidat « héros ».

### 4.5 Réinitialisation

```
/probe off                        # soi-même : tout réactiver (plage connue + dernier single)
/probe off <pseudo>               # admin
/probe off all                    # tous les humains — urgence
```

**Plage connue à réactiver :** constante `PROBE_KNOWN_RANGE` en tête de `server/__init__.lua` (défaut `871087115`–`871087135`) + dernier `actionId` single + toute plage du dernier `/probe range`.

---

## 5. Commandes chat — grammaire

Préfixe proposé : `/probe` (insensible à la casse côté parsing).

| Commande | Description |
|----------|-------------|
| `/probe help` | Liste des commandes |
| `/probe single <id> [pseudo]` | Mode §4.1 |
| `/probe range <debut> <fin> [pseudo]` | Mode §4.2 |
| `/probe enableone <id> [pseudo]` | Mode §4.4 |
| `/probe auto on \| off` | Mode §4.3 |
| `/probe off [pseudo \| all]` | §4.5 |
| `/probe status` | Affiche cible, IDs désactivés, mode auto |

**Restriction admin (recommandée) :** seuls les messages dont le pseudo est dans `PROBE_ADMINS` (table Lua en tête de fichier) peuvent cibler un **autre** joueur ou `off all`. Sinon uniquement soi-même.

**Pattern d’écoute :** `ServerPlayer:SendMessage` — filtrer les messages commençant par `/probe` (voir `HVVPlaygroundPlugin`).

---

## 6. Constantes (code)

| Constante | Défaut | Description |
|-----------|--------|-------------|
| `PROBE_KNOWN_RANGE_MIN` | `871087115` | Borne basse réactivation `/probe off` |
| `PROBE_KNOWN_RANGE_MAX` | `871087135` | Borne haute |
| `PROBE_DELAY_SEC` | `1.5` | Délai avant sonde auto post-mort |
| `PROBE_ADMINS` | `{ "TonPseudo" }` | Pseudos autorisés à cibler les autres |

Référence GunGame (classes, **ne pas confondre avec héros**) :

| ID | Usage GunGame |
|----|----------------|
| `871087120` | Colonne gauche |
| `871087121` | Colonne milieu |
| `871087126` | Colonne droite |

---

## 7. Logs et format de sortie

Chaque action loguée :

```text
[DeployActionProbe] single player=Pseudo actionId=871087122 enabled=false
```

En fin de session playtest, exporter manuellement vers le tableau de [methodologie-decouverte-actionid-deploiement.md](./methodologie-decouverte-actionid-deploiement.md) §3.

Option v0.2 : commande `/probe report` qui `print` une ligne CSV des IDs encore désactivés pour la cible.

---

## 8. Sécurité et bonnes pratiques

| Risque | Mitigation |
|--------|------------|
| Joueur bloqué au déploiement | `/probe off` ; `Disconnect` → réactiver toute la plage connue |
| Range trop large | Documenter ; limiter `fin - debut <= 50` en code |
| Bot / joueur absent | Vérifier `not player.isBot` ; `GetPlayer` non nil |
| Oubli du plugin sur serveur public | Ne pas inclure dans le volume plugins production ; README « dev only » |

---

## 9. Critères d’acceptation (plugin sonde)

- [ ] `/probe single` désactive un ID pour un joueur sans affecter les autres clients.
- [ ] `/probe off` restaure la sélection sur la plage configurée.
- [ ] `/probe range` + `/probe enableone` permettent d’isoler au moins un ID qui bloque **uniquement** le slot héros (validation humaine).
- [ ] `Disconnect` déclenche réactivation (pas d’état persistant cassé).
- [ ] Logs lisibles avec `KYBER_LOG_LEVEL=debug`.

---

## 10. Liens

- [Méthodologie playtest actionId](./methodologie-decouverte-actionid-deploiement.md)
- [Spec BattlepointBalancer](./spec-battlepoint-equilibrage.md) §4.3.3
- [Lancer un serveur avec plugins](./lancer-serveur-avec-plugins.md)
- Code : `GunGame/server/input_blocks.lua`, `HVVPlaygroundPlugin/server/__init__.lua` (chat)

---

## Changelog spec

| Version | Date | Changements |
|---------|------|-------------|
| 0.1 | 2026-05-29 | Première spec plugin sonde |
