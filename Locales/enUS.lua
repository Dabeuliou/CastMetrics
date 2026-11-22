local _, ns = ...

local ui = {
	HELP_HEADER = "Available commands:",
	HELP_CONFIG = "Open graphical options panel",
	HELP_DMG = "Toggle center stat display",
	HELP_CASTS = "Toggle remaining casts counter",
	HELP_TOOLTIP = "Toggle tooltip stats (DPM, HPM, DPS)",
	HELP_MODE = "Cycle center stat (avg / weighted / range / crit / dpm / dps)",
	HELP_COMPACT = "Toggle compact number format (1.4k)",
	HELP_DEBUG = "Inspect tooltip of a slot (or hovered button)",

	CMD_CENTER_STAT = "Center stat: %s",
	CMD_CASTS = "Remaining casts: %s",
	CMD_TOOLTIP = "Tooltip stats: %s",
	CMD_COMPACT = "Compact format: %s",
	STATE_ON = "ON",
	STATE_OFF = "OFF",

	DEBUG_HEADER = "Inspecting %s=%s (Retail=%s, Locale=%s):",
	DEBUG_EMPTY_SLOT = "No action in this slot.",
	DEBUG_NO_TOOLTIP = "C_TooltipInfo returned no usable data.",
	DEBUG_NO_PARSER_MATCH = "Parser -> no values detected.",

	SPELL_FALLBACK_NAME = "Spell #%s",
	PREVIEW_HEADER = "Button preview (live)",
	PREVIEW_HINT = "Hover the sample button to inspect its enriched tooltip as well.",
	PREVIEW_NO_SPELL = "No damage/healing spell found on your action bars",

	OPT_STAT_AVG = "Base average (Direct + DoT/HoT)",
	OPT_STAT_WEIGHTED = "Weighted average (with crit %)",
	OPT_STAT_RANGE = "Range (Min-Max)",
	OPT_STAT_CRIT = "Estimated critical strike",
	OPT_STAT_DPM = "Efficiency (DPM / HPM / DPR)",
	OPT_STAT_DPS = "DPS / HPS (by cast time)",
	OPT_PREVIEW_AUTO = "Automatic (1st spell on bars)",

	OPT_SHOW_DAMAGE = "Show center stat",
	OPT_SHOW_DAMAGE_TT = "Shows or hides the value displayed at the center of action buttons.",
	OPT_CENTER_STAT = "Center stat",
	OPT_CENTER_STAT_TT = "Choose which statistic is displayed at the center of each action button.",
	OPT_CENTER_FONT_SIZE = "Center text size",
	OPT_CENTER_FONT_SIZE_TT = "Adjusts the font size at the center of the button (useful for reading large DPM or DPS values).",
	OPT_SHOW_CASTS = "Show remaining casts",
	OPT_SHOW_CASTS_TT = "Displays in the bottom-right corner how many times you can cast the spell with your current resource.",
	OPT_CASTS_FONT_SIZE = "Casts counter size",
	OPT_CASTS_FONT_SIZE_TT = "Adjusts the font size of the remaining casts counter in the bottom-right corner.",
	OPT_HIDE_ON_COOLDOWN = "Hide center stat while on cooldown",
	OPT_HIDE_ON_COOLDOWN_TT = "Hides the center number while a spell is on cooldown (excluding GCD) so it does not overlap cooldown timers.",
	OPT_COMPACT_NUMBERS = "Short format for large numbers (1.4k)",
	OPT_COMPACT_NUMBERS_TT = "Abbreviates numbers >= 1000 on buttons (e.g. 1450 -> 1.4k).",
	OPT_SHOW_TOOLTIP_STATS = "Show detailed stats in tooltip",
	OPT_SHOW_TOOLTIP_STATS_TT = "Adds average, crit-weighted average, DPM/HPM, and DPS/HPS to spell tooltips.",
	OPT_PREVIEW_SPELL = "Preview spell",
	OPT_PREVIEW_SPELL_TT = "Choose one of your spells to preview your settings on the sample button below.",
	OPT_COMBAT_LOCKED = "Cannot open options while in combat.",

	RES_MANA = "Mana",
	RES_RAGE = "Rage",
	RES_ENERGY = "Energy",
	RES_FOCUS = "Focus",
	RES_GENERIC = "Res.",
	WORD_HEALING = "Healing",
	WORD_DAMAGE = "Damage",
	TAG_CAST = "%.1fs cast",
	TAG_GCD = "%.2gs GCD",
	TAG_CD = "%s CD",
	COMBO_PT_SINGULAR = " (%d pt)",
	COMBO_PT_PLURAL = " (%d pts)",

	TT_TOTAL_AVG = "Total %s (avg)%s",
	TT_DIRECT_PERIODIC = "  Direct / Periodic",
	TT_TOTAL_DURATION = "Total %s (%gs)%s",
	TT_AVERAGE = "Average %s%s",
	TT_CRIT = "Crit (%s)",
	TT_CRIT_TICK = "Crit / tick (%s)",
	TT_WEIGHTED_AVG_PCT = "Crit-weighted avg (%.1f%%)",
	TT_PER_SEC_VALUE = "%.1f / s",
	TT_PER_GCD = "%s per GCD (%s)",
	TT_PERIODIC_DPS = "Periodic %s (%gs)",
	TT_REMAINING_CASTS = "Remaining casts",
}

local parser = {
	thousandPattern = "(%d)[ ,](%d%d%d)",
	ignoreLineWords = { "seated" },

	healDetectPatterns = {
		"heals?[%s%p]",
		"healing",
		"restores?%s+%d+[%.,]?%d*%%?.-health",
	},
	damageDetectPatterns = {
		"%d+[^%.]-damage",
		"weapon damage",
	},

	healContextWords = { "heals?[%s%p]", "healing", "restores?[%s%p].-health", "health" },
	damageContextWords = { "damage", "deals?[%s%p]", "inflicts?[%s%p]" },

	schoolPatterns = {
		{ school = 2, words = { "holy damage", "holy" } },
		{ school = 3, words = { "fire damage", "fire" } },
		{ school = 4, words = { "nature damage", "nature" } },
		{ school = 5, words = { "frost damage", "frost" } },
		{ school = 6, words = { "shadow damage", "shadow" } },
		{ school = 7, words = { "arcane damage", "arcane" } },
		{ school = 1, words = { "physical damage", "bleed", "weapon damage", "physical" } },
	},

	chunkPatterns = {
		{ pattern = "(%d+)%s+to%s+(%d+)[^%.]-damage", kind = "damage", range = true },
		{ pattern = "(%d+)%s+to%s+(%d+)[^%.]-health", kind = "heal", range = true, requiresLineKind = "heal" },
		{ pattern = "for%s+(%d+)%s+to%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
		{ pattern = "heals?%s+(%d+)%s+to%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
		{ pattern = "restores?%s+(%d+)%s+to%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
		{ pattern = "another%s+(%d+)%s+to%s+(%d+)", useLineKind = true, range = true },
		{ pattern = "additional%s+(%d+)%s+to%s+(%d+)", useLineKind = true, range = true },
		{ pattern = "(%d+)%s+%a+%s+damage", kind = "damage", range = false },
		{ pattern = "(%d+)%s+damage", kind = "damage", range = false },
		{ pattern = "weapon damage[^%d]*plus%s+(%d+)", kind = "damage", range = false },
		{ pattern = "heals?[^%d%%%.]*(%d+[%.,]?%d*)%s*%%%s+[^%.]-health", kind = "heal", requiresLineKind = "heal", isHealthPct = true },
		{ pattern = "restores?[^%d%%%.]*(%d+[%.,]?%d*)%s*%%%s+[^%.]-health", kind = "heal", requiresLineKind = "heal", isHealthPct = true },
		{ pattern = "(%d+)%s+health", kind = "heal", range = false, requiresLineKind = "heal" },
		{ pattern = "for%s+(%d+)[%s%.,;]", kind = "heal", range = false, requiresLineKind = "heal", avoidNextWords = { "^secs?", "^mins?", "^yds?", "^yards?", "^targets?", "^allies", "^enem" } },
		{ pattern = "heals?%s+(%d+)", kind = "heal", range = false, requiresLineKind = "heal" },
		{ pattern = "restores?%s+(%d+)", kind = "heal", range = false, requiresLineKind = "heal" },
		{ pattern = "another%s+(%d+)", useLineKind = true, range = false },
		{ pattern = "additional%s+(%d+)", useLineKind = true, range = false },
	},

	comboHintWord = "combo",
	comboLinePatterns = {
		"^%s*(%d+)%s+points?%s*:%s*(.+)$",
	},
	comboRangePatterns = {
		"^(%d+)%s+to%s+(%d+)",
		"^(%d+)%s*%-%s*(%d+)",
	},

	durationUnitPatterns = {
		{ pattern = "(%d)%s+s([%s%p])", replacement = "%1 sec%2" },
		{ pattern = "(%d)%s+secs?([%s%p])", replacement = "%1 sec%2" },
	},
	intervalDurationPatterns = {
		"every%s+([%d%.,]+)%s+sec.-for%s+([%d%.,]+)%s+sec",
	},
	perSecDurationPatterns = {
		"every%s+sec.-for%s+([%d%.,]+)%s+sec",
		"per sec.-for%s+([%d%.,]+)%s+sec",
	},
	overDurationPatterns = {
		"^[^%.,%d]*over%s+([%d%.,]+)%s+sec",
	},
	forDurationPatterns = {
		"^([^%.,%d]*)for%s+([%d%.,]+)%s+sec",
	},
	beforeDurationPatterns = {
		"over%s+([%d%.,]+)%s+sec[^%d]*$",
	},
	cooldownSecPatterns = {
		"([%d%.,]+)%s+sec%s+cooldown",
		"([%d%.,]+)%s+sec%s+recharge",
	},
	cooldownMinPatterns = {
		"([%d%.,]+)%s+min%s+cooldown",
		"([%d%.,]+)%s+min%s+recharge",
	},
	conjunctionWords = { "and", "plus" },
}

ns.RegisterLocale("enUS", ui, parser)
