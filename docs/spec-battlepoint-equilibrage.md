# Spécification v0.1.6 — Plugin d’équilibrage des battle points (héros)

> **Statut :** spécification de conception — implémentation Lua non démarrée dans ce dépôt.  
> **Public cible :** serveurs **fun only** (Galactic Assault, Supremacy, etc.).  
> **Historique des pistes abandonnées et alternatives non retenues :** [equilibrage_brainstorming.md](./equilibrage_brainstorming.md) (ce document ne décrit que ce qui est **à implémenter**).

## 1. Objectifs

### 1.1 Problème

Dans de nombreux modes, les joueurs accumulent des **battle points** (BP) via objectifs et éliminations, puis dépensent ~**4000 BP** pour jouer un **héros** (personnage achetable au déploiement, kit type `Kit_Hero_*`). Les joueurs déjà en tête gagnent plus souvent → achètent plus de héros → renforcent leur avantage (**richesse qui s’accumule**).

### 1.2 Ressenti visé en fin de partie

- Personne ne monopolise les héros ; chacun a une **chance réaliste** d’en jouer au moins une fois.
- Même un joueur peu performant au combat **s’amuse** (objectifs, comeback).
- **À éviter :** frustration du type « le serveur favorise les meilleurs, je meurs en boucle sans jamais de héros ».

### 1.3 Hors scope et non-objectifs v0.1

**Public et modes**

- Serveurs compétitifs / ranked mindset.
- Modes **HVV**, **Co-op**, **Ewok Hunt**, **Hero Showdown**, **Hero Starfighters** (liste noire §4.6).
- Égaliser le skill pur au gunplay (cible : **économie héros**, pas le K/D global).

**Économie et leviers non utilisés**

- Mod Frostbite pour coûts / taux de gain BP globaux.
- **Prix héros dynamique** par joueur (non exposé par l’API).
- **Prélèvement BP fixe** à chaque passe (type « taxe » périodique sur le solde).
- **Bilan comptable** dons = retraits (injection ou retrait net acceptés — §4.4).
- **File héros virtuelle** : bloquer l’achat héros au menu tant qu’un autre joueur n’a pas ~4000 BP, ou bloquer les dominateurs de façon permanente au déploiement (ancienne piste B).
- **Pause globale** lorsqu’un héros est déjà sur la carte.
- **Malus à taux unique** pour tous les dominateurs éligibles (remplacé par taux **progressif** §4.3.1).
- **Malus sur pic de BP** sur l’intervalle ou **malus à l’achat** au spawn (alternatives documentées dans le brainstorming).

**Détection / UI**

- Overtime et cinématiques (pas d’API phase — §4.7).
- Liste blanche exhaustive des kits héros mods (heuristique `activeKit` — §4.2.1).

### 1.4 Définition « héros »

Dans ce document, **héros** = personnage achetable pour **~4000 BP** au menu de déploiement (slots héros), détectable côté serveur via `player.activeKit` (chemins contenant `/Hero/` ou `Kit_Hero_`).  
**Exclus :** spécialistes, renforts, véhicules héros des modes dédiés.

---

## 2. Architecture plugin (prévue)

```
BattlepointBalancer/   (nom de dossier proposé)
  plugin.json
  common/
    timer.lua          # réutiliser le pattern des exemples
    sdk.lua            # optionnel, copie des helpers existants
  server/
    __init__.lua       # logique principale
```

- Chargement : `common/__init__.lua` (optionnel) puis `server/__init__.lua`.
- Boucle : **`Server:UpdatePre`** (callback moteur **à chaque frame/tick simulation**, avec `deltaSecs` en argument) + accumulateur interne pour n’exécuter la logique métier qu’une fois toutes les `TICK_SEC` secondes (comme `BotBalancer`, `GunGame`). Ce n’est **pas** « un tick = une passe d’équilibrage » : la passe d’équilibrage est **décimée** sur les `UpdatePre`.
- API : `PlayerManager`, `player.battlepoints`, `player.score`, `player.kills`, `player.deaths`, `player.isSpawned`, `GiveBattlepoints` / `SetBattlepoints`, `player.activeKit`, `SetInputEnabled` (cooldown héros uniquement, §4.3.3), `Console.Execute("Kyber.Broadcast ...")`.

---

## 3. Paramètres v1 — variables d’environnement

Quatre réglages **obligatoirement exposés** dès la v1 via `KYBER_PLUGIN_SETTING_*` (lus au chargement du plugin, comme GunGame).

| Variable | Type | Défaut v0.1 | Description |
|----------|------|-------------|-------------|
| `KYBER_PLUGIN_SETTING_FACTOR` | nombre (float) | `0.2` | Facteur appliqué à l’écart de **score** au médian pour calculer le don en BP par tick. |
| `KYBER_PLUGIN_SETTING_TICK_SEC` | nombre (float) | `20` | Intervalle en secondes entre deux passes d’équilibrage. |
| `KYBER_PLUGIN_SETTING_DON_CAP` | entier | `1000` | Plafond de BP donnés à un joueur aidé par tick. |
| `KYBER_PLUGIN_SETTING_MIN_GAP` | entier | `3000` | Écart minimum de **battle points** (max − min parmi les humains) pour activer l’équilibrage. |

### 3.1 Formule de don (aidés)

Pour chaque joueur **éligible à l’aide** (voir §4.2), à chaque tick :

```
ecart_score = max(0, score_median - player.score)
don = min(DON_CAP, floor(ecart_score * FACTOR))
player:GiveBattlepoints(don)
```

`DON_CAP`, `FACTOR` : valeurs lues depuis l’environnement (défauts ci-dessus).

### 3.2 Exemple de parsing Lua (indicatif)

```lua
local function readNumber(envName, default)
    local raw = os.getenv(envName)
    if raw == nil or raw == "" then return default end
    local n = tonumber(raw)
    return n or default
end

local FACTOR = readNumber("KYBER_PLUGIN_SETTING_FACTOR", 0.2)
local TICK_SEC = readNumber("KYBER_PLUGIN_SETTING_TICK_SEC", 20)
local DON_CAP = readNumber("KYBER_PLUGIN_SETTING_DON_CAP", 1000)
local MIN_GAP = readNumber("KYBER_PLUGIN_SETTING_MIN_GAP", 3000)
```

### 3.3 Exemple Docker / dev

```bash
KYBER_PLUGIN_SETTING_FACTOR=0.2
KYBER_PLUGIN_SETTING_TICK_SEC=20
KYBER_PLUGIN_SETTING_DON_CAP=1000
KYBER_PLUGIN_SETTING_MIN_GAP=3000
```

**Playtest :** ajuster `MIN_GAP` et `DON_CAP` en premier si l’économie est trop agressive ; puis `TICK_SEC` ; enfin `FACTOR`.

---

## 4. Règles métier

### 4.1 Activation globale

L’équilibrage **s’exécute** uniquement si **toutes** les conditions suivantes sont vraies :

| # | Condition |
|---|-----------|
| A | Au moins **3** joueurs humains (`not player.isBot`). |
| B | Mode de jeu **non** blacklisté (§4.6). |
| C | Phase **non silencieuse** (§4.7) — heuristique à implémenter. |
| D | `max(battlepoints_humains) - min(battlepoints_humains) > MIN_GAP` |

Si (D) est faux, **aucun** don ni prélèvement ce tick (plugin en veille).

> **Note :** le seuil MIN_GAP porte sur les **battle points**, pas le score.  
> **Début de manche :** tant que les humains ont des BP proches (écart ≤ `MIN_GAP`, souvent tout le monde vers 0), la condition (D) est fausse → le plugin reste en **veille** ; pas besoin de cas particulier `score_median == 0` pour l’activation.

**Effectif 3+ :** dès qu’il y a au moins 3 humains, les **mêmes** règles de médiane, d’aide, de malus et de pénalités héros s’appliquent (pas de variante « petite lobby »). La médiane du score est calculée sur **tous** les humains connectés (tri des scores ; valeur centrale ; si effectif pair, **moyenne des deux valeurs centrales**).

### 4.2 Joueurs aidés (plusieurs)

Un humain est **aidé** s’il remplit **toutes** les conditions :

| # | Règle |
|---|--------|
| 1 | `kills + deaths >= 5` (volume de combat minimum ; évite le join récent). |
| 2 | `score < 0.75 * score_median` (médiane du score des humains). |
| 3 | Éligibilité K/D : voir tableau ci-dessous. |
| 4 | **Pas en héros** : `not isPlayingHero(player)` (§4.2.1). |

**K/D** = `kills / deaths` si `deaths > 0` ; sinon voir cas limites.

| Situation | Aidé ? |
|-----------|--------|
| `deaths == 0` et `kills > 0` (K/D « infini ») | **Non** |
| `kills == 0`, beaucoup de morts, K/D = 0 | **Oui** si score < médian (objectifs) |
| K/D < 0,5 | **Oui** si déjà score < 75 % médian et règle (1) |
| **0,5 ≤ K/D < 1,5** (et score < 75 % médian) | **Non** |

Chaque tick : appliquer la **formule de don** (§3.1) à **tous** les aidés éligibles ce tick.

Les dons utilisent `GiveBattlepoints` **sans exiger** que les BP retirés aux dominateurs couvrent le total (§4.4).

#### 4.2.1 Détection « en héros »

Un joueur est **en héros** lorsqu’il est spawné et que son kit actif est un héros achetable (~4000 BP) :

```lua
local function isPlayingHero(player)
    if not player.isSpawned then return false end
    local kit = player.activeKit
    if kit == nil then return false end
    local name = kit.name or ""
    return string.find(name, "Kit_Hero", 1, true) ~= nil
        or string.find(name, "/Hero/", 1, true) ~= nil
end
```

**Règle :** aucun don si `isPlayingHero(player)` — même si score/K/D éligibles.  
**API :** `player.activeKit` (exposé par KYBER ; utilisé dans `GunGame/server/input_blocks.lua`).

**Limites connues :** heuristique par **nom de kit** (`Kit_Hero`, `/Hero/`). Risque de **faux positifs** (kit mod ou chemin d’asset contenant `/Hero/` sans être un héros à ~4000 BP) ou de **faux négatifs** (héros mod sans ces motifs). À valider en playtest ; pas de liste blanche exhaustive en v0.1.

### 4.3 Joueurs « dominateurs » (pénalités)

Un humain est **dominateur** si :

```
score > 1.25 * score_median  AND  K/D > 1.5   (deaths > 0 requis pour K/D)
```

**But :** ne pas pénaliser un bon joueur d’**objectifs** (score élevé, K/D modeste).

**Pénalités v0.1 (cumulables) :**

1. **Malus de gain BP progressif** — §4.3.1 : taux lié à l’écart de score au **médian** (calculé **à chaque passe** d’équilibrage, pas à chaque `UpdatePre`).
2. **Cooldown héros 120 s** — §4.3.3 : après une session héros, blocage **temporaire** des slots héros au déploiement via `SetInputEnabled`.
3. **Clamp BP en héros** : pendant un run héros, max **+3000 BP** cumulés depuis le spawn héros.

#### 4.3.1 Malus de gain BP — taux progressif

**Éligibilité** (inchangée) — le malus ne s’applique que si :

```
score > 1.25 * score_median  AND  K/D > 1.5   (deaths > 0)
```

**Taux de malus** — proportionnel à l’écart au-dessus du médian, avec bonus fixe de **5 %** :

```
ratio     = player.score / score_median          (si median > 0)
excess    = ratio - 1                            -- 0.25 à 125 % du médian, 0.45 à 145 %, etc.
TAUX_MALUS = min(MALUS_CAP, excess + MALUS_BASE)

MALUS_BASE = 0.05   (les « +5 % »)
MALUS_CAP  = 0.70   (plafond du taux)
```

**Application** (une fois par passe d’équilibrage, même fréquence que les dons — voir §4.8) :

```
ΔBP = battlepoints_maintenant − battlepoints_snapshot_fin_passe_précédente
si player.isSpawned et ΔBP > 0 :
  retrait = min(player.battlepoints, floor(ΔBP * TAUX_MALUS))
  GiveBattlepoints(-retrait)
```

**Écran de déploiement :** le malus ne s’applique **pas** si `not player.isSpawned` (joueur mort / en attente de respawn sur l’écran de sélection ou de customisation). Évite de taxer les gains **passifs** pendant le choix du personnage, des cartes ou de l’apparence (§4.3.4).

**Plancher retrait :** ne jamais retirer plus que `player.battlepoints` (même pattern que `GunGame/server/__init__.lua` au transfert BP au kill).

**Exemples** (`MALUS_BASE = 0,05`, médian = 10 000) :

| Score joueur | % du médian | `excess` | `TAUX_MALUS` | Sur +800 BP gagnés |
|--------------|-------------|----------|--------------|---------------------|
| 12 500 | 125 % | 0,25 | **30 %** | −240 BP |
| 13 500 | 135 % | 0,35 | **40 %** | −320 BP |
| 14 500 | 145 % | 0,45 | **50 %** | −400 BP |
| 16 500 | 165 % | 0,65 | **70 %** (cap) | −560 BP |

Un dominateur à **145 %** du médian est donc plus taxé qu’un autre à **125 %**, même si tous deux passent le seuil d’éligibilité.

**Lua indicatif :**

```lua
local MALUS_BASE <const> = 0.05
local MALUS_CAP <const> = 0.70

local function gainMalusRate(playerScore, scoreMedian)
    if scoreMedian <= 0 then return 0 end
    local excess = (playerScore / scoreMedian) - 1
    if excess <= 0 then return 0 end
    local rate = excess + MALUS_BASE
    if rate > MALUS_CAP then rate = MALUS_CAP end
    return rate
end
```

**v2 env (prévu) :** `KYBER_PLUGIN_SETTING_MALUS_BASE`, `KYBER_PLUGIN_SETTING_MALUS_CAP`.

#### 4.3.2 Malus et dépenses BP (héros / véhicule)

Si un dominateur **dépense** des BP (héros ~4000, véhicule, etc.), le **ΔBP net** sur la passe est souvent **négatif** → **pas de malus** cette passe (`ΔBP > 0` uniquement, §4.3.1). Comportement voulu : la dépense vide déjà la réserve ; le cooldown et le clamp héros complètent.

#### 4.3.3 Cooldown héros 120 s — `SetInputEnabled`

**Rôle de l’API :** `player:SetInputEnabled(actionId, enabled)` active ou désactive une **action du menu de déploiement** identifiée par un entier `actionId` (côté moteur, entrée du joueur sur un slot / une colonne du déploiement). Ce n’est **pas** une modification du coût BP : le joueur voit toujours son solde ; on empêche (ou réautorise) la **sélection** d’un slot.

À la **fin** d’une session héros (`ServerPlayer:Killed` ou sortie de kit détectée par poll `activeKit` entre deux passes), démarrer un timer **120 s** pour ce joueur dominateur ; pendant le délai, `SetInputEnabled(..., false)` sur les **actionId des slots héros** (par joueur, par slot — §1.3). Réactiver à expiration. Technique proche de `GunGame/server/input_blocks.lua` ; IDs **héros** : [methodologie-decouverte-actionid-deploiement.md](./methodologie-decouverte-actionid-deploiement.md), [spec-deploy-action-probe.md](./spec-deploy-action-probe.md).

**Fin de session héros :** `ServerPlayer:Killed` ; si le joueur change de kit sans mourir, comparer `isPlayingHero` entre deux passes (pas d’event dédié).

#### 4.3.4 BP, déploiement et écran de sélection

- Le plugin ne distingue pas « en train de choisir » vs « en jeu » : il lit `player.battlepoints` et `player.isSpawned`.
- **Hypothèse moteur (à valider en playtest) :** la dépense ~4000 BP pour un héros intervient à la **confirmation du déploiement / spawn**, pas à l’ouverture de la carte héros. Tant que le joueur n’a pas spawné, le solde affiché reste celui du serveur.
- **Malus :** avec la règle `isSpawned` (§4.3.1), pas de malus sur l’écran de sélection classique (souvent `isSpawned == false` après une mort).
- **Dons :** peuvent toujours s’appliquer en veille déploiement si le joueur est éligible et la passe globale est active — en pratique rare au début de manche (MIN_GAP).

### 4.4 Économie BP

Le plugin **n’impose pas** l’égalité comptable dons / retraits (injection ou retrait net possibles). Objectif : **ressenti fun** et rotation héros. Dons et malus sur ΔBP sont des leviers **indépendants**.

Le malus dominateur s’applique à **tous** ceux au-dessus de 125 % du médian avec K/D > 1,5 — pas seulement au #1 au score.

### 4.5 Héros — coût effectif

- Coût moteur : **~4000 BP** (non modifiable par joueur via l’API actuelle).
- Leviers plugin : malus sur ΔBP, clamp en session héros, cooldown au déploiement (`SetInputEnabled`, §4.3.3).

### 4.6 Modes — liste noire

Désactiver le plugin (aucun tick) pour les `gameModeId` correspondant à :

- HVV  
- Co-op  
- Ewok Hunt  
- Hero Showdown  
- Hero Starfighters  

Implémentation : même pattern que la whitelist de `BotBalancer` (`ResourceManager:PartitionLoaded` → `GameModeInformationAsset`), en **liste noire**.

### 4.7 Phases silencieuses

Ne pas équilibrer pendant :

- Déploiement initial de la manche  
- Fin de manche / rotation de carte  
- *(Souhaité mais non fiable en v0.1 :)* overtime, cinématiques / transitions  

**Contrainte API :** pas de phase de partie (déploiement, OT, cinématique) exposée en Lua.

**Sémantique Kyber (validée) :**

| Event | Moment réel |
|-------|-------------|
| `Level:Loaded` | **Début** du chargement d’une carte (pas « la partie a commencé »). |
| `Level:Complete` | **Fin** de la manche (avant chargement de la suivante). |

→ **Ne pas** utiliser « silencieux entre `Level:Loaded` et `Level:Complete` » : cela couvrirait **toute** la manche.

**Heuristique v0.1 (actée) :**

1. **`Level:Complete`** → désactiver toute passe d’équilibrage jusqu’au prochain chargement utile.  
2. **`Level:Loaded`** (mode non blacklisté) → réinitialiser un délai de grâce **`DEPLOY_GRACE_SEC`** (constante code v0.1, ex. **90 s**) : **aucune** passe pendant ce délai (couvre le déploiement initial et le temps de premier spawn).  
3. Après expiration du délai → passes autorisées si §4.1 (A–D) OK.  
4. **Overtime / cinématiques** : non détectables en v0.1 ; risque résiduel accepté ou atténué par playtest des durées de tick.

Constante `DEPLOY_GRACE_SEC` : documentée en code ; passage en `KYBER_PLUGIN_SETTING_*` possible en v2.

### 4.8 Ordre des opérations à une passe d’équilibrage

À chaque passe (toutes les `TICK_SEC`, pas à chaque `UpdatePre`) :

1. Vérifier activation globale §4.1 (dont phase non silencieuse §4.7). Si faux → mettre à jour les snapshots BP uniquement si besoin, puis sortir.  
2. Calculer `score_median` et l’écart BP humain (condition D).  
3. **Malus ΔBP** sur les dominateurs **spawnés** (`isSpawned`) — §4.3.1.  
4. **Dons** aux joueurs aidés — §3.1 / §4.2.  
5. **Clamp +3000 BP** en session héros — §4.3 (sur gains depuis le spawn héros).  
6. **Snapshots** `battlepoints` en fin de passe (référence pour le ΔBP de la passe suivante).  

**Hors passe :** cooldown `SetInputEnabled` (timers / events) ; détection fin de session héros (poll + `Killed`).

---

## 5. Communication joueur

| Moment | Message (exemple) |
|--------|-------------------|
| Début de manche (mode autorisé) | `Kyber.Broadcast` — **« Mode Équilibrage actif »** |
| Contribution dominateur (espacé, ex. max 1 / 3 min) | **« Mécène : &lt;pseudo&gt; »** (pas « Robin des bois ») |
| Ajustement économique (optionnel, debug / faible fréquence) | Message court discret |

Pas de spam à chaque tick.

---

## 6. Scénarios de référence

**Hypothèses :** médiane score = 10 000 → aide si score < 7 500 ; dominateur si score > 12 500 et K/D > 1,5 ; MIN_GAP = 3000 ; défauts FACTOR/TICK_SEC/DON_CAP.

### 6.1 Huit joueurs en GA

- Écart BP max − min > 3000 → actif.  
- Bas du tableau : dons jusqu’à 1000 BP / 20 s.  
- Dominateur avec 5 200 BP : malus progressif + cooldown → ne enchaîne pas les héros.  
- Joueur milieu (bon score objectifs, K/D 1,2) : **ni aidé ni dominateur**.

### 6.2 Tryhard 18k score

- Dominateur confirmé → malus progressif sur gains + cooldown / clamp héros.  
- Dernier à 400 BP : plafond 1000 / 20 s → fenêtre héros en ~1–2 min si non contesté.  
- Le tryhard peut encore dominer à l’infanterie.

### 6.3 Arrivée mi-partie

- Avant 5 kills+deaths : **pas d’aide**.  
- Ensuite, si score < 75 % médian et K/D éligible → aidé.

---

## 7. Paramètres futurs (hors env v1, documentés)

À exposer en `KYBER_PLUGIN_SETTING_*` ou `Console.Register` dans une version ultérieure :

| Paramètre | Valeur discutée | Rôle |
|-----------|-----------------|------|
| Seuil aide score | `0.75` × médian | Ratio score aidé |
| Seuil dominateur score | `1.25` × médian | Ratio score pénalisé |
| K/D aide max | `0.5` | Plafond K/D pour aide |
| K/D dominateur min | `1.5` | Plancher K/D pour pénalité |
| Combat minimum | `5` | kills + deaths |
| Cooldown héros | `120` s | Anti-enchaînement |
| Gain max en héros | `3000` BP | Clamp session héros |
| Malus base (`MALUS_BASE`) | `0.05` | Constante ajoutée à `excess` (+5 %) |
| Malus plafond (`MALUS_CAP`) | `0.70` | Taux max sur les gains BP |
| `DEPLOY_GRACE_SEC` | `90` | Silence après `Level:Loaded` (§4.7) |
| Coût héros effectif | `4000` | Référence moteur |

---

## 8. Risques et tests

| Risque | Mitigation |
|--------|------------|
| API plugins expérimentale | Tests GA / Supremacy sur serveur de dev |
| Pas d’event BP | Snapshots + malus ΔBP à chaque passe (§4.8) |
| Phases déploiement | `DEPLOY_GRACE_SEC` + veille `Level:Complete` (§4.7) |
| Faux positifs `isPlayingHero` | Playtest kits ; heuristique nom (§4.2.1) |
| Malus sur écran déploiement | `isSpawned` requis (§4.3.1, §4.3.4) |
| Farming score entre amis | Médiane + seuil MIN_GAP |
| Double compte / AFK bas du tableau | Volume combat + score < 75 % médian |
| Trop rapide vers 4000 BP | Baisser DON_CAP ou monter TICK_SEC |

**Checklist playtest v0.1 :**

- [ ] MIN_GAP 3000 : activation / veille correcte  
- [ ] Défauts 0,2 / 20 s / 1000 : rythme ressenti fun, pas inflation totale  
- [ ] Dominateur K/D 1,4 / score 130 % médian : **non** pénalisé  
- [ ] Dominateur K/D 1,6 / score 130 % médian : pénalisé, pas de spam héros  
- [ ] Nouveau joueur &lt; 5 engagements : pas de don  
- [ ] Mode blacklisté : plugin inactif  
- [ ] Variables env surchargées bien prises en compte au redémarrage  

---

## 9. Liens

- [Brainstorming et historique](./equilibrage_brainstorming.md)  
- [Méthodologie découverte actionId déploiement](./methodologie-decouverte-actionid-deploiement.md)  
- [Spec plugin sonde DeployActionProbe](./spec-deploy-action-probe.md)  
- [Lancer un serveur avec plugins](./lancer-serveur-avec-plugins.md)  
- Exemples : `GunGame/` (BP), `BotBalancer/` (timer, game modes)  
- Sources moteur : `E:\workspace\Kyber_w_lan\Module\Source\Script\LuaPlayerManager.cpp`

---

## Changelog spec

| Version | Date | Changements |
|---------|------|-------------|
| 0.1.6 | 2026-05-29 | Allègement spec : non-objectifs §1.3 ; pistes rejetées → brainstorming uniquement |
| 0.1.5 | 2026-05-29 | Phases silencieuses corrigées ; K/D 0,5–1,5 ; cooldown `SetInputEnabled` ; malus si `isSpawned` ; ordre passe §4.8 ; limites `isPlayingHero` |
| 0.1.4 | 2026-05-28 | §4.3.2 dépense BP au tick — option 1 (malus sur ΔBP net uniquement) |
| 0.1.3 | 2026-05-28 | `MALUS_CAP` 0,70 acté ; économie non à l’équilibre ; pas de prélèvement fixe |
| 0.1.2 | 2026-05-28 | Malus gain progressif : `TAUX = min(cap, (score/médian − 1) + 5 %)` |
| 0.1.1 | 2026-05-28 | Piste B écartée ; pas d’aide si en héros ; propositions malus/prélèvement §4.3.1 |
| 0.1 | 2026-05-28 | Première spec : règles consolidées, 4 env vars, défauts 0,2 / 20 / 1000 / 3000 |
