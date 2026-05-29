# Brainstorming — Équilibrage battle points / héros

> Récapitulatif des échanges de conception (conversation agent + utilisateur).  
> **Spec formalisée :** [spec-battlepoint-equilibrage.md](./spec-battlepoint-equilibrage.md) (v0.1).  
> **Implémentation :** non démarrée au moment de ce document.

## Contexte initial

**Problème SWBF2 / KYBER :** les joueurs gagnent des battle points (BP) via objectifs et kills, puis dépensent ~**4000 BP** pour un **héros** au déploiement. Les meilleurs accumulent plus → achètent plus de héros → boucle d’avantage.

**Question initiale :** un plugin peut-il donner des points au plus faible et en retirer au plus fort ?

**Réponse technique (validée sur le dépôt) :** oui — `player.battlepoints`, `GiveBattlepoints`, `PlayerManager.GetPlayers()`, timer `Server:UpdatePre`. GunGame fait déjà un transfert au kill. Pas d’event Lua « battlepoints changed » (hook C++ présent mais non exposé).

**Plugin vs mod :** pour une redistribution **dynamique par joueur**, le **plugin Lua** est le bon outil ; un mod Frosty convient plutôt aux réglages **statiques** globaux (coûts, taux de gain du mode).

---

## Fil de décisions (utilisateur)

### Philosophie & public

- Serveur **fun only**, pas compétitif.
- Fin de partie visée : tout le monde a eu **au moins une chance** de héros ; les mauvais scores s’amusent quand même (objectifs).
- À éviter : sentiment « le serveur favorise les meilleurs, je spawn en boucle sans héros ».

### Équité ressentie & identité

- Annoncer un **« Mode Équilibrage »** au démarrage de la manche.
- Titre pour le contributeur : **« Mécène »** (rejet de « Robin des bois » — risque de moquerie).
- Messages **discrets**, pas de spam par tick.

### Qui est aidé ?

- **Plusieurs** joueurs, pas un seul « dernier ».
- Critères retenus :
  - Score **< 75 % du score médian** (abandon de la règle « 2× moins de BP que le 1er »).
  - K/D **< 0,5** en général.
  - **0 kill, beaucoup de morts** : aidé si score **< médian** (joueur d’objectifs).
  - **0 mort, quelques kills** (K/D infini) : **pas** d’aide.
  - **Volume de combat** : `kills + deaths >= 5` avant toute aide (anti join récent).
  - **Pas d’aide pendant un run héros** : si le joueur est actuellement en kit héros (`activeKit`), il n’est pas éligible aux dons ce tick (évite de financer un joueur déjà en Vador).

### Qui est pénalisé ?

- **Pas uniquement le #1** (le #2 proche hériterait trop de l’avantage).
- Seuil : score **> 125 % du médian** **ET** K/D **> 1,5**.
- **Taux progressif** sur les gains BP : `(score / médian − 1) + 5 %` (plafond ~70 %) — ex. 125 % → 30 %, 145 % → 50 %.
- Intention : ne pas punir le bon joueur d’**objectifs** (score haut, K/D modeste).
- Préférence : **difficulté à en gagner** (malus sur ΔBP), pas le même taux pour tous les dominateurs.

### Activation globale

- Plugin actif seulement si écart de **battle points** entre le **1er et le dernier** humain **> MIN_GAP** (défaut **3000**, **configurable** pour playtest).
- Minimum **3** humains.
- Modes **off** : HVV, Co-op, Ewok Hunt, Hero Showdown, Hero Starfighters.

### Rythme économique (dons)

- Formule discutée : `don = min(PLAFOND, (score_médian - score) × FACTEUR)`.
- **Médiane** pour le plafond de don : robuste contre le farm à deux comptes.
- **Défauts validés pour spec v0.1 :** FACTEUR **0,2**, tick **20 s**, plafond **1000** BP.
- Comparaison écartée : 0,15 / 30 s (plus doux).
- **v1 :** exposer `KYBER_PLUGIN_SETTING_FACTOR`, `TICK_SEC`, `DON_CAP`, `MIN_GAP`.

### Dominateur & héros

- Objectif : empêcher d’**enchaîner** les héros (~4000 BP).
- Idées utilisateur :
  - Héros plus cher pour les dominateurs → **pas d’API prix dynamique** ; contournement par blocage menu / clamp BP.
  - Malus **-50 %** de gain BP → faisable par **poll** du delta entre ticks.
  - Sinon **cooldown 2 min** après un run héros.
- Plafond **+3000 BP** gagnés pendant une session héros (poll).
- **Piste B — file héros / blocage menu dominateurs** : **non retenue** (décision utilisateur) — pas de `SetInputEnabled` sur les slots héros pour bloquer l’achat.

### Rejeté ou reporté

- **Piste B** (file héros virtuelle, blocage menu tant qu’un aidé &lt; 4000 BP) : **écartée**.
- **Boss fight** / renforcer le leader : non souhaité.
- **Pause** quand un héros est sur la carte : proposé en brainstorming, **rejeté** (ralentit la rotation héros pour tous).
- **Cygne noir** / perfection : accepté comme risque résiduel.

### Phases silencieuses

- Pas d’équilibrage : déploiement, overtime, cinématiques — **à implémenter** (pas de phase Lua exposée ; heuristiques à explorer).

### Clarification terminologie

- **Héros** = achetable **~4000 BP** au déploiement (`Kit_Hero_*`), aligné entre utilisateur et spec.

---

## Piste A — scénarios (résumé)

| Scénario | Idée clé |
|----------|----------|
| 8 joueurs GA | Gap BP > 3000, dons aux < 75 % médian, dominateur : malus progressif + cooldown héros |
| Tryhard 18k score | Pénalités fortes ; bas du tableau monte vers 4000 BP en ~1–2 min si plafond 1000/20 s ; skill gunplay inchangé |
| Nouveau mi-partie | Pas d’aide avant 5 kills+deaths ; puis aide si score/K/D OK |

Détail : section 6 de la spec.

---

## Faisabilité technique (synthèse)

| Capacité | Faisabilité |
|----------|-------------|
| Lire score, K/D, BP | Oui |
| Don / retrait BP | Oui (`GiveBattlepoints`) |
| Timer 20 s | Oui (`Server:UpdatePre` + timer) |
| Détecter héros (en jeu) | Oui — `player.isSpawned` + `player.activeKit.name` contient `Kit_Hero` ou `/Hero/` (comme GunGame) |
| Bloquer achat héros (menu) | Possible (`SetInputEnabled`) mais **hors scope** (Piste B rejetée) |
| Prix héros différent par joueur | Non (moteur) ; seuil effectif 4000 + clamp |
| Malus % gain BP | Partiel (poll ΔBP entre ticks) |
| Phases déploiement / OT | Incertain (pas d’API phase) |

### Détection « joueur en héros » (technique)

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

À valider en playtest sur tous les héros du mode (noms de kits mods éventuels). Cas limite : transition au spawn (1–2 ticks de retard possible).

---

## Pénalités dominateurs — malus progressif (acté)

**Problème des paquets à taux fixe :** deux joueurs éligibles (score > 125 % médian, K/D > 1,5) étaient taxés pareil malgré un écart de score important.

**Solution retenue (utilisateur) — malus sur les gains (A), indexé sur le médian :**

```
excess     = (score / score_median) - 1
TAUX_MALUS = min(MALUS_CAP, excess + 0.05)    -- le « +5 % »
```

| Score (% du médian) | Malus sur ΔBP gagnés |
|---------------------|-------------------------|
| 125 % | 30 % |
| 135 % | 40 % |
| 145 % | 50 % |
| 165 %+ | 70 % (cap acté) |

- Toujours conditionné par **K/D > 1,5** et **score > 125 %** du médian (seuil d’éligibilité).
- **Abandon** des paquets « 30 / 40 / 50 % fixes » pour tous les dominateurs.

**Autres leviers :** cooldown héros 2 min, clamp +3000 BP en session héros.  
**Prélèvement fixe par tick** : **abandonné**.

**Constantes actées :** `MALUS_BASE = 0,05`, `MALUS_CAP = 0,70`.

**Économie :** pas de bilan à l’équilibre — OK si le plugin **injecte plus** de BP qu’il n’en retire (ou l’inverse). Pas besoin que les dons soient « payés » par les dominateurs.

**v2 env (proposé) :** `KYBER_PLUGIN_SETTING_MALUS_BASE`, `KYBER_PLUGIN_SETTING_MALUS_CAP`.

---

## Dépense de BP au tick (héros / véhicule) — option 1 actée

**Question posée :** au moment du tick, si on doit taxer un dominateur mais qu’il vient de **dépenser** ses BP (achat héros ~4000, véhicule, etc.), que faire ?

### Comportement retenu (option 1)

Le malus ne s’applique que sur le **ΔBP net** entre deux ticks :

```
ΔBP = battlepoints_maintenant − battlepoints_au_tick_précédent
si ΔBP > 0 alors reprise de floor(ΔBP × TAUX_MALUS)
```

- **Achat héros / véhicule** → forte baisse du solde → souvent **ΔBP ≤ 0** → **pas de malus ce tick**.
- Ce n’est pas considéré comme une faille : la dépense est déjà une **sortie d’économie** (objectif : ne pas hoarder pour enchaîner les héros).
- **Plancher :** ne jamais retirer plus que `player.battlepoints` (pattern GunGame).

**Exemple :** 5 000 BP au tick N → +900 en jeu → achat héros −4 000 → 1 900 BP au tick N+1 → ΔBP = −3 100 → **aucun malus**, même s’il a gagné 900 BP dans l’intervalle.

### Pourquoi c’est acceptable (v1)

- Cooldown **2 min** après run héros, **clamp +3000 BP** en héros, **pas d’aide** si en kit héros.
- Héros et véhicules partagent le **même pool BP** ; le malus ne distingue pas le type d’achat.

### Options écartées (pour mémoire)

| Option | Description | Statut |
|--------|-------------|--------|
| **2 — Pic de BP** | Mémoriser `bp_peak` sur l’intervalle et taxer `(peak − bp_début_tick)` même après une grosse dépense | Reporté ; si abuse « timing » achat avant tick en playtest |
| **3 — Malus au spawn héros** | Prélèvement à l’achat / `ServerPlayer:Spawned` si dominateur | Non retenu ; ne couvre pas bien le véhicule seul |

### Implémentation

- v1 : **option 1 uniquement**.
- Détail spec : [spec-battlepoint-equilibrage.md](./spec-battlepoint-equilibrage.md) §4.3.2.

---

## Axes restants à explorer

### Implémentation

- [ ] Nom final du dossier plugin (`BattlepointBalancer` ?).
- [x] `MALUS_CAP` = 0,70 — acté.
- [x] Pas de prélèvement fixe ; économie non à l’équilibre — acté.
- [ ] Sémantique exacte `Level:Loaded` vs `Level:Complete` pour la fenêtre de déploiement.
- [ ] Liste noire : IDs `gameModeId` réels (à collecter en log au chargement des maps).
- [ ] Détection fin de session héros (mort, changement kit, déconnexion) pour cooldown 2 min.
- [ ] Valider `isPlayingHero()` sur tous les kits héros vanilla (et mods courants).

### Game design / playtest

- [ ] Défauts 0,2 / 20 s / 1000 : valider le temps moyen pour atteindre 4000 BP.
- [ ] Seuils 75 % / 125 % médian et K/D 0,5 / 1,5 : cas limites en stomp 12 vs 12.
- [ ] AFK en bas du classement : faut-il un seuil de mouvement / score stagnant ?
- [ ] Équipes déséquilibrées : médiane globale vs par équipe ?

### Communication

- [ ] Fréquence max des messages « Mécène ».
- [ ] Message quand le plugin passe en **veille** (gap < MIN_GAP).

### Paramétrage v2

- [ ] Exposer en env : ratios 0,75 / 1,25, K/D seuils, cooldown 120, combat min 5, malus 0,5.
- [ ] `Console.Register` pour admins in-game.

### Documentation / dépôt

- [ ] Ajouter les 4 variables dans `docs/lancer-serveur-avec-plugins.md` §8 quand le plugin existe.
- [ ] Entrée README PluginExamples.
- [ ] Règle cursor `kyber-plugins.mdc` : ligne pour le nouveau plugin.

### Hors scope discuté

- Mod Frostbite coût héros global.
- Équilibrage véhicules / enforcers.
- Client UI (plugins client dépréciés).

---

## Références conversation

- Transcript Cursor : [session équilibrage BP](2b943cb3-3d60-4985-8901-1db6a044137d) (questions initiales plugin vs mod, brainstorming facilitateur).
- Code existant : `GunGame/server/__init__.lua` (BP), `GunGame/server/input_blocks.lua` (kits), `BotBalancer/server/__init__.lua` (modes, timer).

---

## Prochaine étape suggérée

1. Valider la spec v0.1 sur le papier (ce document + spec).  
2. Implémenter `BattlepointBalancer/` minimal : lecture env, timer, activation MIN_GAP, dons seuls.  
3. Ajouter malus gain progressif + cooldown héros + exclusion aide si `isPlayingHero`.  
4. Playtest et ajuster les `KYBER_PLUGIN_SETTING_*` (+ paquet pénalités retenu).
