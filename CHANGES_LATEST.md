## [1.4.0-beta.2] - 2026-11-22

### Added
- Automatically hide the center damage/healing stat while a spell is on a real cooldown (excluding the GCD and spells with remaining charges), keeping cooldown countdown numbers clearly readable.
- New **"Hide center stat while on cooldown"** option in `/cm config` (enabled by default), localized across `enUS`, `frFR`, `deDE`, and `esES`.
- Support Retail 12.1.5 secret cooldown values via `DurationObject` (`SetAlphaFromBoolean` / `isOnGCD`) with fallback support for WoW Forever (`16001`).

### Fixed & Optimized
- Eliminated framerate drops when spamming spell keys:
  - Removed unnecessary full tooltip re-parses on `ACTIONBAR_UPDATE_STATE`.
  - Skip hidden action buttons until shown (`OnShow`) and avoid re-parsing tooltips on `UpdateAction` / `OnButtonUpdate` when the spell has not changed.
  - Coalesced GCD cooldown hook updates and throttled `UNIT_AURA` refreshes in combat.
