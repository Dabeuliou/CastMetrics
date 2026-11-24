# Changelog

All notable changes to **CastMetrics** are documented in this file.

## [1.4.2-beta.2] - 2026-11-24

### Added
- Display the active addon version (`vX.Y.Z`) directly in `/cm debug` output.

---

## [1.4.2-beta.1] - 2026-11-22

### Added
- **Weapon-damage spell scaling**: Calculate actual damage for percentage weapon-damage abilities (such as *Backstab* / *Attaque sournoise*) across `enUS`, `frFR`, `deDE`, and `esES` using `UnitDamage("player")` and `UnitRangedDamage("player")` (main-hand, off-hand, ranged, and flat `+bonus` modifiers), with combat caching.

### Fixed
- Fallback to joined tooltip lines when a damage description wraps across a line break without combo-point tiers.

---

## [1.4.1] - 2026-11-22

### Added
- **Center Remaining Casts mode**: Added **"Remaining casts (center only)"** to the center statistic options in `/cm config` and `/cm mode`, including resource-costing utility/buff spells, while automatically disabling and greying out the bottom-right casts checkbox.
- **Remaining Casts Display Threshold**: Added a **"Display threshold (max casts)"** slider (`0–100`, `0 = All`) in `/cm config` to hide the casts counter above your threshold (safe in combat with Retail *secret values* via `C_CurveUtil`).

---

## [1.4.0] - 2026-11-22

*Special thanks to **Vax** for suggesting cooldown hiding, spotting the key-spam framerate drop, and beta-testing this release!*

### Added
- Automatically hide the center damage/healing stat while a spell is on a real cooldown (excluding the GCD and spells with remaining charges), keeping cooldown countdown numbers clearly readable.
- New **"Hide center stat while on cooldown"** option in `/cm config` (enabled by default), localized across `enUS`, `frFR`, `deDE`, and `esES`.
- Support Retail 12.1.5 secret cooldown values via `DurationObject` (`SetAlphaFromBoolean` / `isOnGCD`) with fallback support for WoW Forever (`16001`).

### Fixed & Optimized
- Eliminated framerate drops when spamming spell keys:
  - Removed unnecessary full tooltip re-parses on `ACTIONBAR_UPDATE_STATE`.
  - Skip hidden action buttons until shown (`OnShow`) and avoid re-parsing tooltips on `UpdateAction` / `OnButtonUpdate` when the spell has not changed.
  - Coalesced GCD cooldown hook updates and throttled `UNIT_AURA` refreshes in combat.

---

## [1.3.1] - 2026-11-22

### Added
- Support max-health percentage heals (such as *Frenzied Regeneration*) using cached `UnitHealthMax` (safe against *secret values* in combat).
- Parse periodic tick intervals (such as *Efflorescence*) across `enUS`, `frFR`, `deDE`, and `esES` and track total tick count.

### Changed
- Replace unrealistic all-ticks max crit with per-tick crit on pure DoTs/HoTs.
- Display the active crit chance alongside the weighted average line.
- Factor spell cooldowns into sustained DPS/HPS calculations (`CD` tag) and distinguish periodic rate from per-GCD value on non-cooldown DoTs/HoTs.

### Fixed
- Respect non-crittable spells (`canCrit = false`) so spells like *Frenzied Regeneration* no longer display crit estimates.

---

## [1.3.0] - 2026-11-22

### Added
- Multi-language UI and locale-aware tooltip parsing for `enUS`/`enGB`, `frFR`, `deDE`, and `esES`/`esMX` (with automatic `enUS` fallback).
- Localized addon descriptions (`Notes-*`) in `CastMetrics.toc`.

---

## [1.2.1] - 2026-11-21

### Added
- Dynamic combo-point scaling (1–N points) on action buttons, tooltips, and live preview.

### Fixed
- Improved WoW tooltip markup cleanup (`|cn`, `|4`, `|T`, `|A`, non-breaking spaces) and additional DoT/HoT segments.

---

## [1.2.0] - 2026-11-21

### Added
- Support for **Bartender4** and **LibActionButton-1.0** action bars (**ElvUI**, **Dominos**).

---

## [1.1.0] - 2026-11-21

### Changed
- Renamed addon to **CastMetrics** and added **WoW Retail** (`120105`) support alongside **WoW Forever** (`16001`).

---

## [1.0.1] - 2026-11-18

### Fixed
- Prevented false-positive tooltip parsing on shapeshifts, buffs, and food items.

---

## [1.0.0] - 2026-11-17

### Added
- Initial release with customizable action button overlays, remaining cast counter, detailed tooltip breakdown (Crit, Weighted Average, DPM/HPM, DPS/HPS), and native options panel with live preview (`/cm config`).
