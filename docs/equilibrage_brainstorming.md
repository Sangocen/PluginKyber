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

### Qui est pénalisé ?

- **Pas uniquement le #1** (le #2 proche hériterait trop de l’avantage).
- Règle : score **> 125 % du médian** **ET** K/D **> 1,5**.
- Intention : ne pas punir le bon joueur d’**objectifs** (score haut, K/D modeste).
- Préférence : **perte continue de BP** et/ou **difficulté à en gagner**, plutôt qu’un gros coup unique.

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
- **File d’attente héros virtuelle** : souhaitée si faisable → v0.1 prévoit blocage menu dominateurs tant qu’un aidé < 4000 BP (pattern GunGame `SetInputEnabled`).

### Rejeté ou reporté

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
| 8 joueurs GA | Gap BP > 3000, dons aux < 75 % médian, dominateur bloqué côté héros |
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
| Détecter héros | Oui (`player.activeKit.name`) |
| Bloquer achat héros | Oui (`SetInputEnabled`, GunGame) |
| Prix héros différent par joueur | Non (moteur) ; seuil effectif 4000 + clamp |
| Malus -50 % gain BP | Partiel (poll ΔBP) |
| File d’attente moteur | Non ; file **virtuelle** possible |
| Phases déploiement / OT | Incertain (pas d’API phase) |

---

## Axes restants à explorer

### Implémentation

- [ ] Nom final du dossier plugin (`BattlepointBalancer` ?).
- [ ] Montant exact du **prélèvement** dominateur par tick et répartition si plusieurs dominateurs.
- [ ] Sémantique exacte `Level:Loaded` vs `Level:Complete` pour la fenêtre de déploiement.
- [ ] Liste noire : IDs `gameModeId` réels (à collecter en log au chargement des maps).
- [ ] IDs `SetInputEnabled` pour les slots héros (reprendre / étendre GunGame).
- [ ] Détection fin de session héros (mort, changement kit, déconnexion).

### Game design / playtest

- [ ] Défauts 0,2 / 20 s / 1000 : valider le temps moyen pour atteindre 4000 BP.
- [ ] Seuils 75 % / 125 % médian et K/D 0,5 / 1,5 : cas limites en stomp 12 vs 12.
- [ ] Comportement si **un seul** dominateur mais **plusieurs** aidés (déséquilibre du financement).
- [ ] AFK en bas du classement : faut-il un seuil de mouvement / score stagnant ?
- [ ] Équipes déséquilibrées : médiane globale vs par équipe ?

### File héros virtuelle (Piste B — non tranchée)

- [ ] Soft (bonus BP seulement) vs Medium (blocage menu) vs Hard (cooldown + taxe spawn).
- [ ] Si **tous** les aidés dépassent 4000 BP en même temps : règle de priorité (ordre score ?).

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
3. Ajouter pénalités dominateur + blocage héros + cooldown.  
4. Playtest et ajuster les quatre `KYBER_PLUGIN_SETTING_*`.
