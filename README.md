# CastMetrics (WoW Retail & Forever)

Addon inspiré de **DrDamage** pour **World of Warcraft Retail** (`Interface: 120105`) et **WoW Forever** (`Interface: 16001`), conçu aussi comme support d'apprentissage de **Lua**.

## Fonctionnalités

- **Compatible barres natives & addons de barres** : fonctionne avec les barres Blizzard, **Bartender4**, **ElvUI** (`LibActionButton-1.0`) et **Dominos**.
- **Statistique personnalisable centrée sur le bouton** : lue dynamiquement depuis le tooltip (`C_TooltipInfo.GetAction`), en cumulant dégâts/soins directs et effets sur la durée (DoT / HoT).
  - Or/orange pour les dégâts, vert pour les soins.
- **Nombre de lancers possibles en bas à droite du bouton** : calculé selon la ressource du sort (Mana, Rage, Énergie, Focalisation, Essence…), avec prise en charge des *secret values* via `UnitPowerPercent` + `C_CurveUtil`.
  - Code couleur dynamique selon la marge restante (bleu → jaune → orange → rouge).
- **Statistiques détaillées dans le tooltip des sorts** : moyenne totale, décomposition Direct + Périodique, coup critique estimé (`×2.0` sur Retail y compris DoT/HoT, `×1.5` en magie / `×2.0` en physique sur Forever), moyenne pondérée avec le critique réel, **DPM / HPM / DPR / DPE**, **DPS / HPS** (avec prise en compte de la Hâte sur Retail) et lancers possibles.
- **Panneau d'options natif** (**Échap → Options → AddOns → CastMetrics**, ou `/cm config`) :
  - Choix de la statistique affichée au centre du bouton : moyenne de base, moyenne pondérée avec critique %, intervalle Min-Max, coup critique estimé, DPM/HPM ou DPS/HPS.
  - Sliders de taille de police pour le texte central et le compteur en bas à droite.
  - Activation/désactivation indépendante du texte central, du compteur de lancers, du format court et des stats dans le tooltip.
  - **Aperçu en direct** avec sélection d'un sort de vos barres d'action.
- **Commandes en jeu (`/cm` ou `/castmetrics`)** :
  - `/cm config` : ouvrir le panneau d'options graphique
  - `/cm dmg` : afficher/masquer la stat centrale
  - `/cm casts` : afficher/masquer le compteur de lancers restants
  - `/cm tooltip` : afficher/masquer les stats dans le tooltip
  - `/cm mode` : faire défiler la stat centrale (`avg`, `weighted`, `range`, `crit`, `dpm`, `dps`)
  - `/cm compact` : activer/désactiver le format court (`1.4k`)
  - `/cm debug [slot]` : inspecter les lignes brutes du tooltip d'un slot (ou du bouton sous le curseur)

## Installation (pour les joueurs)

1. Téléchargez l'archive `CastMetrics-vX.Y.Z.zip`.
2. Extrayez le dossier `CastMetrics` directement dans `...\World of Warcraft\_retail_\Interface\AddOns\` (ou `_forever_\Interface\AddOns\`) pour obtenir `Interface\AddOns\CastMetrics\CastMetrics.toc`.
3. Relancez le jeu (ou `/reload`), vérifiez que **CastMetrics** est coché dans la liste des addons, puis tapez `/cm config` en jeu pour le personnaliser.

## Déployer et partager (développeur)

1. **Déployer en local** : dans **Antigravity IDE**, appuyez sur `Ctrl+Shift+B` (ou **Terminal → Run Build Task...**) pour déployer vers **Retail et WoW Forever** simultanément via [deploy.ps1](deploy.ps1) (des tâches ciblées *Retail uniquement* et *Forever uniquement* sont aussi disponibles dans [.vscode/tasks.json](.vscode/tasks.json)).
2. **Générer un `.zip` de partage** : `Ctrl+Shift+P` → **Tasks: Run Task** → **Packager le .zip de partage** (ou exécutez [package.ps1](package.ps1)).
   - Génère `dist\CastMetrics-v<version>.zip` prêt à être partagé (la version est lue automatiquement dans [CastMetrics.toc](CastMetrics.toc)).

## Ce que chaque fichier vous apprend en Lua

1. `CastMetrics.toc` : manifeste multi-versions lu au démarrage par WoW (`Interface: 120105, 16001`, `SavedVariables`, ordre de chargement des scripts).
2. `Core.lua` : namespace partagé (`local addonName, ns = ...`), détection d'édition (`WOW_PROJECT_ID`), tables de dispatch d'événements, commandes slash et anti-rebond (`C_Timer.After`).
3. `TooltipParser.lua` : manipulation de chaînes et *pattern matching* Lua (`gsub`, `match`, `find`, `gmatch`), capture de groupes et normalisation UTF-8.
4. `ManaCalc.lua` : interrogation des namespaces modernes `C_Spell` / `Enum.PowerType` et gestion des *secret values* avec `C_CurveUtil` + `UnitPowerPercent`.
5. `TooltipStats.lua` : extension du tooltip natif via `TooltipDataProcessor.AddTooltipPostCall` (DPM, HPM, DPS, HPS, crit, Hâte).
6. `ButtonOverlay.lua` : création de `FontString` sur les boutons d'action, `hooksecurefunc` (éviter le *taint*), tables associatives et mise en cache par bouton.
7. `Options.lua` : création d'un panneau de configuration natif via l'API moderne `Settings` (`RegisterVerticalLayoutCategory`, `RegisterProxySetting`, `CreateCheckbox`, `CreateDropdown`, `CreateSlider`) et bouton d'aperçu en direct.
