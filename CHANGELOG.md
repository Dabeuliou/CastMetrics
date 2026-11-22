# Changelog

All notable changes to **CastMetrics** are documented in this file.

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
