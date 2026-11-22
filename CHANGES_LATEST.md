## [1.4.0-beta.1] - 2026-11-22

### Added
- Automatically hide the center damage/healing stat while a spell is on a real cooldown (excluding the GCD and spells with remaining charges), keeping cooldown countdown numbers clearly readable.
- New **"Hide center stat while on cooldown"** option in `/cm config` (enabled by default), localized across `enUS`, `frFR`, `deDE`, and `esES`.
- Support Retail 12.1.5 secret cooldown values via `DurationObject` (`SetAlphaFromBoolean` / `isOnGCD`) with fallback support for WoW Forever (`16001`).
