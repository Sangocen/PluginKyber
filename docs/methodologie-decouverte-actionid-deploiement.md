# Méthodologie — Découverte des `actionId` de déploiement (slots héros)

> **Objectif :** trouver les entiers passés à `player:SetInputEnabled(actionId, enabled)` qui correspondent aux **slots héros** du menu de déploiement (~4000 BP), pour le cooldown du [BattlepointBalancer](./spec-battlepoint-equilibrage.md).  
> **Outil recommandé :** plugin [DeployActionProbe](./spec-deploy-action-probe.md) (spec + implémentation à venir dans ce dépôt).

---

## 1. Rappels API

### 1.1 `SetInputEnabled` est **par joueur** et **par action**

```lua
unJoueur:SetInputEnabled(actionId, false)
```

- N’affecte **que** `unJoueur`, pas tout le serveur.
- Chaque `actionId` = une entrée du menu (colonne classe, slot héros, etc.), **pas** un héros précis (Vador vs Luke partagent en général le même slot / la même action).
- Pour bloquer **uniquement** les héros en cooldown : appeler `false` sur **chaque** ID validé comme « slot héros », et **ne pas** toucher aux IDs infanterie / véhicule.

### 1.2 IDs déjà connus dans PluginExamples (classes, pas héros)

| actionId | Source | Effet attendu |
|----------|--------|-----------------|
| `871087120` | GunGame — gauche | Colonne classe gauche |
| `871087121` | GunGame — milieu | Colonne classe milieu |
| `871087126` | GunGame — droite | Colonne classe droite |

Les IDs héros sont **à découvrir** ; ils sont souvent dans la même famille numérique (`8710871xx`) mais **il faut le prouver en jeu**.

---

## 2. Prérequis playtest

| Élément | Détail |
|---------|--------|
| Serveur | Dédié ou local KYBER, **dev uniquement** |
| Plugin | `DeployActionProbe` via `KYBER_DEV_PLUGIN_PATH` |
| Logs | `KYBER_LOG_LEVEL=debug` |
| Mode | **Galactic Assault** ou **Supremacy** (déploiement classique + héros) |
| Joueurs | 1 testeur minimum ; **2 recommandés** (vérifier que le blocage est individuel) |
| BP | Assez de BP pour voir les héros débloqués (~4000) — console admin ou partie avancée |

**À éviter pour la première passe :** HVV, Hero Showdown, Co-op (UI différente ou mode hors scope équilibrage).

---

## 3. Tableau de collecte

Copier ce tableau dans un fichier perso ou en commentaire de PR :

| actionId | Héros bloqué ? | Classe inf. bloquée ? | Véhicule bloqué ? | Mode + map | Date | Validé (oui/non) |
|----------|----------------|------------------------|-------------------|------------|------|------------------|
| | | | | | | |

**Critère « ID héros retenu » :**

- `Héros bloqué ?` = **oui**
- `Classe inf.` et `Véhicule` = **non** (sur la même map / mode)
- Confirmé par `/probe off` puis `true` → tout redevient sélectionnable
- Confirmé sur un **deuxième** joueur non sondé → pas de blocage chez lui

---

## 4. Procédure A — Un ID à la fois (recommandée)

La plus fiable ; utilise le mode **single** du plugin sonde.

### Étapes

1. Lancer le serveur avec `DeployActionProbe` et rejoindre en GA.
2. Jouer jusqu’à avoir **≥ 4000 BP** (ou utiliser une commande admin BP si disponible).
3. **Mourir** pour ouvrir l’écran de déploiement.
4. Sur le serveur (chat) :  
   `/probe single 871087122`  
   (remplacer par l’ID à tester ; commencer autour de `871087115`–`871087135`).
5. **Observer côté client :**
   - Peut-on encore choisir **Assault / Officer / …** ?
   - Peut-on encore choisir un **véhicule** (si affiché) ?
   - La ligne / le slot **héros** est-il grisé ou impossible à valider ?
6. Noter une ligne dans le tableau §3.
7. `/probe off` — tout doit redevenir normal.
8. Passer à l’ID suivant (`871087123`, …).

### Ordre de balayage suggéré (première passe)

```text
871087115, 871087116, … 871087135   (entiers un par un, pas de pas de 10)
```

Puis élargir si aucun résultat : `871087100`–`871087150`, ou demander la communauté Kyber.

### Durée indicative

~2–3 min par ID en mode manuel → la plage de 21 IDs ≈ **45–60 min** pour une première passe complète.

---

## 5. Procédure B — Balayage rapide puis affinage

Plus rapide, moins lisible ; mode **range** + **enableone**.

### B.1 Désactiver toute la plage

1. Mourir → écran déploiement.
2. `/probe range 871087115 871087135`
3. Noter globalement : « plus rien », « seulement héros », « tout bloqué y compris classes », etc.

| Observation | Interprétation |
|-------------|----------------|
| Tout bloqué | La plage contient des IDs critiques ; réduire ou utiliser **enableone** |
| Rien ne change | Mauvaise plage — élargir ou vérifier que le plugin tourne côté serveur |
| Classes OK, héros KO | Bonne plage — passer à B.2 |

### B.2 Réactiver un ID à la fois

1. `/probe range` laisse tout à `false`.
2. `/probe enableone 871087115` — le héros redevient-il sélectionnable ?
3. Si **non** : cet ID n’est probablement **pas** le slot héros seul (ou il faut plusieurs IDs).
4. `/probe off`, recommencer range, puis `enableone` sur `871087116`, etc.

Quand **enableone** sur un ID fait **réapparaître** le slot héros alors que les classes restent OK → cet ID est un **candidat fort** ; valider avec la procédure A sur cet ID seul.

---

## 6. Procédure C — Validation croisée (obligatoire avant prod)

Pour chaque `actionId` retenu :

| # | Test | Résultat attendu |
|---|------|------------------|
| 1 | `/probe single <id>` sur testeur A | Héros bloqué, classes OK |
| 2 | `/probe off` | Tout OK |
| 3 | Testeur B **sans** commande probe | Aucun blocage |
| 4 | Répéter sur une **deuxième map** GA ou Supremacy | Même IDs ou noter la différence |
| 5 | Après **spawn** infanterie, `/probe off` + respawn | Pas de blocage résiduel |

Si les IDs diffèrent entre GA et Supremacy, documenter **deux listes** ou la liste la plus restrictive selon le design du `BattlepointBalancer`.

---

## 7. Mode auto (optionnel)

Si le plugin implémente `/probe auto on` :

1. `/probe single 871087122`
2. `/probe auto on`
3. Enchaîner mort → déploiement : la sonde se réapplique après ~1,5 s sans retaper la commande.

Utile pour affiner l’observation UI ; ne remplace pas la procédure C.

---

## 8. Après découverte — intégration

### 8.1 Constantes dans BattlepointBalancer (futur)

```lua
-- Validé : GA Kashyyyk, 2026-05-29 — voir methodologie-decouverte-actionid-deploiement.md
local HERO_DEPLOY_ACTION_IDS <const> = {
    871087122,  -- exemple fictif jusqu'à playtest
}
```

### 8.2 Mise à jour spec équilibrage

Dans [spec-battlepoint-equilibrage.md](./spec-battlepoint-equilibrage.md) §4.3.3, ajouter un tableau « IDs validés » avec mode, map, date.

### 8.3 Retirer la sonde

Désactiver `KYBER_DEV_PLUGIN_PATH` vers `DeployActionProbe` sur tout serveur non dev.

---

## 9. Dépannage

| Symptôme | Piste |
|----------|--------|
| Aucun effet UI | Vérifier logs `[DeployActionProbe]` ; mauvais pseudo ; pas en écran déploiement |
| Tout le menu bloqué | `/probe off all` ; plage trop large |
| Classes bloquées, pas héros | ID = colonne classe (proche 120/121/126), pas héros — continuer le balayage |
| Héros toujours sélectionnable | Mauvais ID ; ou plusieurs IDs héros à bloquer tous |
| Blocage chez tout le monde | Oubli : `SetInputEnabled` doit être sur **un** player ; vérifier le code sonde |

---

## 10. Plan B (si aucun ID héros isolé)

1. Publier les résultats (tableau + mode) sur le Discord / issues Kyber.
2. Cooldown `BattlepointBalancer` **sans** `SetInputEnabled` : malus ΔBP + clamp +3000 en héros uniquement.
3. Sanction au `ServerPlayer:Spawned` si héros + cooldown actif (UX dure — dernier recours).

---

## 11. Liens

- [Spec plugin sonde](./spec-deploy-action-probe.md)
- [Spec BattlepointBalancer](./spec-battlepoint-equilibrage.md)
- [Lancer un serveur avec plugins](./lancer-serveur-avec-plugins.md)
- Code : `GunGame/server/input_blocks.lua`

---

## Changelog

| Version | Date | Changements |
|---------|------|-------------|
| 0.1 | 2026-05-29 | Première version méthodologie playtest |
