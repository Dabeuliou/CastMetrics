## [1.4.2-beta.1] - 2026-11-22

### Added
- **Weapon-damage spell scaling**: Calculate actual damage for percentage weapon-damage abilities (such as *Backstab* / *Attaque sournoise*, *Sinister Strike*, *Mortal Strike*, etc.) across `enUS`, `frFR`, `deDE`, and `esES` using `UnitDamage("player")` and `UnitRangedDamage("player")` (supporting main-hand, off-hand, and ranged weapons, plus optional flat bonuses like `plus 51`).
- Cache weapon damage values on login, shapeshift, and equipment changes to stay compatible with *secret values* in combat.

### Fixed
- Fallback to joined tooltip lines when a damage description wraps across a line break without combo-point tiers.
