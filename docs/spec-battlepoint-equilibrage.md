# Spécification v0.1 — Plugin d’équilibrage des battle points (héros)

> **Statut :** spécification de conception — implémentation Lua non démarrée dans ce dépôt.  
> **Public cible :** serveurs **fun only** (Galactic Assault, Supremacy, etc.).  
> **Référence brainstorming :** [equilibrage_brainstorming.md](./equilibrage_brainstorming.md)

## 1. Objectifs

### 1.1 Problème

Dans de nombreux modes, les joueurs accumulent des **battle points** (BP) via objectifs et éliminations, puis dépensent ~**4000 BP** pour jouer un **héros** (personnage achetable au déploiement, kit type `Kit_Hero_*`). Les joueurs déjà en tête gagnent plus souvent → achètent plus de héros → renforcent leur avantage (**richesse qui s’accumule**).

### 1.2 Ressenti visé en fin de partie

- Personne ne monopolise les héros ; chacun a une **chance réaliste** d’en jouer au moins une fois.
- Même un joueur peu performant au combat **s’amuse** (objectifs, comeback).
- **À éviter :** frustration du type « le serveur favorise les meilleurs, je meurs en boucle sans jamais de héros ».

### 1.3 Hors scope v0.1

- Serveurs compétitifs / ranked mindset.
- Modes **HVV**, **Co-op**, **Ewok Hunt**, **Hero Showdown**, **Hero Starfighters**.
- Égaliser le skill pur au gunplay (le plugin cible l’**économie héros**, pas le K/D global).
- Mod Frostbite pour changer les coûts héros côté client (complément possible plus tard).

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
- Boucle : `Server:UpdatePre` + timer (comme `BotBalancer`, `GunGame`).
- API : `PlayerManager`, `player.battlepoints`, `player.score`, `player.kills`, `player.deaths`, `GiveBattlepoints` / `SetBattlepoints`, `player.activeKit`, `SetInputEnabled` (file héros virtuelle), `Console.Execute("Kyber.Broadcast ...")`.

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

### 4.2 Joueurs aidés (plusieurs)

Un humain est **aidé** s’il remplit **toutes** les conditions :

| # | Règle |
|---|--------|
| 1 | `kills + deaths >= 5` (volume de combat minimum ; évite le join récent). |
| 2 | `score < 0.75 * score_median` (médiane du score des humains). |
| 3 | Éligibilité K/D : voir tableau ci-dessous. |

**K/D** = `kills / deaths` si `deaths > 0` ; sinon voir cas limites.

| Situation | Aidé ? |
|-----------|--------|
| `deaths == 0` et `kills > 0` (K/D « infini ») | **Non** |
| `kills == 0`, beaucoup de morts, K/D = 0 | **Oui** si score < médian (objectifs) |
| K/D < 0,5 | **Oui** si déjà score < 75 % médian et règle (1) |

Chaque tick : appliquer la **formule de don** (§3.1) à **tous** les aidés.

Le financement des dons provient des **dominateurs** (§4.3), pas d’une création ex nihilo de BP (à valider en implémentation : répartition du prélèvement).

### 4.3 Joueurs « dominateurs » (pénalités)

Un humain est **dominateur** si :

```
score > 1.25 * score_median  AND  K/D > 1.5   (deaths > 0 requis pour K/D)
```

**But :** ne pas pénaliser un bon joueur d’**objectifs** (score élevé, K/D modeste).

**Pénalités v0.1 (cumulables) :**

1. **Prélèvement léger** chaque tick (montant à calibrer en implémentation, fraction du don total ou fixe paramétrable plus tard).
2. **Malus de gain BP (~50 %)** : entre deux ticks, si `ΔBP > 0`, reprendre `floor(ΔBP * 0.5)` sur le dominateur (poll ; pas d’event Lua `BattlepointsChanged` exposé).
3. **Cooldown héros 120 s** après une session héros (détection `activeKit` héros → fin sur `ServerPlayer:Killed` ou sortie de kit).
4. **File héros virtuelle (medium)** : tant qu’au moins un joueur aidé a `battlepoints < 4000`, bloquer le menu héros des dominateurs via `SetInputEnabled` (pattern `GunGame/server/input_blocks.lua`).
5. **Clamp BP en héros** : pendant un run héros, limiter le gain cumulé à **3000 BP** depuis le spawn héros (poll ; mémoire du solde au spawn).

**Rejeté :** pause globale « un héros est déjà sur la carte ».

### 4.4 Répartition du financement

- Ne pas cibler **uniquement** le #1 aux BP ou au score.
- Prélèvement réparti sur l’ensemble des **dominateurs** (§4.3).

### 4.5 Héros — coût effectif

- Coût moteur : **~4000 BP** (non modifiable par joueur via l’API actuelle).
- Contournements plugin : blocage menu, clamp, prélèvement, cooldown — pas de « prix héros dynamique » natif en v0.1.

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

- Déploiement initial  
- Overtime  
- Cinématiques / transitions  

**Contrainte API :** pas de phase de partie exposée en Lua. Pistes :

- Désactiver entre `Level:Loaded` et `Level:Complete` (ou inverse selon sémantique moteur à vérifier dans Kyber_w_lan).  
- Délai configurable après `Level:Complete` avant première passe.  
- Flag manuel admin (hors v0.1).

**Statut :** [OPEN] — valider les events en jeu.

---

## 5. Communication joueur

| Moment | Message (exemple) |
|--------|-------------------|
| Début de manche (mode autorisé) | `Kyber.Broadcast` — **« Mode Équilibrage actif »** |
| Contribution dominateur (espacé, ex. max 1 / 3 min) | **« Mécène : &lt;pseudo&gt; »** (pas « Robin des bois ») |
| Ajustement économique (optionnel, debug / faible fréquence) | Message court discret |

Pas de spam à chaque tick.

---

## 6. Scénarios de référence (Piste A)

**Hypothèses :** médiane score = 10 000 → aide si score < 7 500 ; dominateur si score > 12 500 et K/D > 1,5 ; MIN_GAP = 3000 ; défauts FACTOR/TICK_SEC/DON_CAP.

### 6.1 Huit joueurs en GA

- Écart BP max − min > 3000 → actif.  
- Bas du tableau : dons jusqu’à 1000 BP / 20 s.  
- Dominateur avec 5 200 BP : blocage ou malus → ne enchaîne pas les héros.  
- Joueur milieu (bon score objectifs, K/D 1,2) : **ni aidé ni dominateur**.

### 6.2 Tryhard 18k score

- Dominateur confirmé → prélèvement + malus + blocage héros.  
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
| Malus gain BP | `0.5` | Fraction de ΔBP reprise |
| Coût héros effectif | `4000` | Référence file virtuelle |

---

## 8. Risques et tests

| Risque | Mitigation |
|--------|------------|
| API plugins expérimentale | Tests GA / Supremacy sur serveur de dev |
| Pas d’event BP | Poll + malus ΔBP |
| Phases déploiement | Heuristiques + logs `KYBER_LOG_LEVEL=debug` |
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
- [Lancer un serveur avec plugins](./lancer-serveur-avec-plugins.md)  
- Exemples : `GunGame/` (BP), `BotBalancer/` (timer, game modes)  
- Sources moteur : `E:\workspace\Kyber_w_lan\Module\Source\Script\LuaPlayerManager.cpp`

---

## Changelog spec

| Version | Date | Changements |
|---------|------|-------------|
| 0.1 | 2026-05-28 | Première spec : règles consolidées, 4 env vars, défauts 0,2 / 20 / 1000 / 3000 |
