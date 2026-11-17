# CastsButtonDisplay (WoW Forever)

Addon inspiré de **DrDamage** pour **World of Warcraft: Forever** (`Interface: 16001` / client `1.60.1`), conçu aussi comme support d'apprentissage de **Lua**.

## Fonctionnalités

- **Dégâts / soins centrés sur le bouton** : lus dynamiquement depuis le tooltip (`C_TooltipInfo.GetAction`), en cumulant dégâts/soins directs et effets sur la durée (DoT / HoT).
  - Or/orange pour les dégâts, vert pour les soins.
- **Nombre de lancers possibles en bas à droite du bouton** : calculé selon la ressource du sort (Mana, Rage, Énergie, Focalisation…), avec prise en charge des *secret values* via `UnitPowerPercent` + `C_CurveUtil`.
  - Code couleur dynamique selon la marge restante (bleu → jaune → orange → rouge).
- **Statistiques détaillées dans le tooltip des sorts** : moyenne totale, décomposition Direct + Périodique, critique estimé (×1.5), **DPM / HPM / DPR / DPE**, **DPS / HPS** (temps d'incantation / GCD et périodique) et lancers possibles.
- **Panneau d'options natif** (**Échap → Options → AddOns → CastsButtonDisplay**, ou `/cbd config`) :
  - Choix de la statistique affichée au centre du bouton : moyenne de base, moyenne pondérée avec critique %, intervalle Min-Max, coup critique estimé, DPM/HPM ou DPS/HPS.
  - Sliders de taille de police pour le texte central et le compteur en bas à droite.
  - Activation/désactivation indépendante du texte central, du compteur de lancers, du format court et des stats dans le tooltip.
- **Commandes en jeu (`/cbd`)** :
  - `/cbd config` : ouvrir le panneau d'options graphique
  - `/cbd dmg` : afficher/masquer la stat centrale
  - `/cbd casts` : afficher/masquer le compteur de lancers restants
  - `/cbd tooltip` : afficher/masquer les stats dans le tooltip
  - `/cbd mode` : faire défiler la stat centrale (`avg`, `weighted`, `range`, `crit`, `dpm`, `dps`)
  - `/cbd compact` : activer/désactiver le format court (`1.4k`)
  - `/cbd debug [slot]` : inspecter les lignes brutes du tooltip d'un slot (ou du bouton sous le curseur)

## Installation (pour les joueurs)

1. Téléchargez l'archive `CastsButtonDisplay-vX.Y.Z.zip`.
2. Extrayez le dossier `CastsButtonDisplay` directement dans `...\World of Warcraft\_forever_\Interface\AddOns\` (vous devez obtenir `Interface\AddOns\CastsButtonDisplay\CastsButtonDisplay.toc`).
3. Relancez le jeu (ou `/reload`), vérifiez que **CastsButtonDisplay** est coché dans la liste des addons, puis tapez `/cbd config` en jeu pour le personnaliser.

## Déployer et partager (développeur)

1. **Déployer en local** : dans **Antigravity IDE**, appuyez sur `Ctrl+Shift+B` (ou **Terminal → Run Build Task...** → **Deployer vers WoW Forever**).
   - Cela exécute [deploy.ps1](deploy.ps1) via [.vscode/tasks.json](.vscode/tasks.json) et copie uniquement les fichiers de l'addon (`.toc`, `.lua`, `.xml`) vers `E:\World of Warcraft\_forever_\Interface\AddOns\CastsButtonDisplay`.
2. **Générer un `.zip` de partage** : `Ctrl+Shift+P` → **Tasks: Run Task** → **Packager le .zip de partage** (ou exécutez [package.ps1](package.ps1)).
   - Génère `dist\CastsButtonDisplay-v<version>.zip` prêt à être envoyé sur Discord, Google Drive ou une **GitHub Release** (la version est lue automatiquement dans `CastsButtonDisplay.toc`).

## Ce que chaque fichier vous apprend en Lua

1. `CastsButtonDisplay.toc` : manifeste lu au démarrage par WoW (`Interface: 16001`, `SavedVariables`, ordre de chargement des scripts).
2. `Core.lua` : namespace partagé (`local addonName, ns = ...`), tables de dispatch d'événements, commandes slash et anti-rebond (`C_Timer.After`).
3. `TooltipParser.lua` : manipulation de chaînes et *pattern matching* Lua (`gsub`, `match`, `find`, `gmatch`), capture de groupes et normalisation UTF-8.
4. `ManaCalc.lua` : interrogation des namespaces modernes `C_Spell` / `Enum.PowerType` et gestion des *secret values* avec `C_CurveUtil` + `UnitPowerPercent`.
5. `TooltipStats.lua` : extension du tooltip natif via `TooltipDataProcessor.AddTooltipPostCall` (DPM, HPM, DPS, HPS, crit).
6. `ButtonOverlay.lua` : création de `FontString` sur les boutons d'action, `hooksecurefunc` (éviter le *taint*), tables associatives et mise en cache par bouton.
7. `Options.lua` : création d'un panneau de configuration natif via l'API moderne `Settings` (`RegisterVerticalLayoutCategory`, `RegisterProxySetting`, `CreateCheckbox`, `CreateDropdown`, `CreateSlider`).
