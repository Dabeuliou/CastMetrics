local _, ns = ...

if ns.LOCALE ~= "deDE" then
	return
end

local ui = {
	HELP_HEADER = "Verfügbare Befehle:",
	HELP_CONFIG = "Grafisches Optionsmenü öffnen",
	HELP_DMG = "Zentralen Wert ein-/ausblenden",
	HELP_CASTS = "Verbleibende Zauber ein-/ausblenden",
	HELP_TOOLTIP = "Tooltip-Statistiken (DPM, HPM, DPS) ein-/ausblenden",
	HELP_MODE = "Zentralen Wert wechseln (avg / weighted / range / crit / dpm / dps)",
	HELP_COMPACT = "Kompaktes Zahlenformat umschalten (1.4k)",
	HELP_DEBUG = "Tooltip eines Aktionsplatzes (oder Buttons unter dem Mauszeiger) prüfen",

	CMD_CENTER_STAT = "Zentraler Wert: %s",
	CMD_CASTS = "Verbleibende Zauber: %s",
	CMD_TOOLTIP = "Tooltip-Statistiken: %s",
	CMD_COMPACT = "Kompaktformat: %s",
	STATE_ON = "EIN",
	STATE_OFF = "AUS",

	DEBUG_HEADER = "Prüfung %s=%s (Retail=%s, Locale=%s):",
	DEBUG_EMPTY_SLOT = "Keine Aktion auf diesem Platz.",
	DEBUG_NO_TOOLTIP = "C_TooltipInfo hat keine verwertbaren Daten geliefert.",
	DEBUG_NO_PARSER_MATCH = "Parser -> keine Werte erkannt.",

	SPELL_FALLBACK_NAME = "Zauber #%s",
	PREVIEW_HEADER = "Button-Vorschau (live)",
	PREVIEW_HINT = "Fahre mit der Maus über den Beispiel-Button, um auch seinen erweiterten Tooltip zu prüfen.",
	PREVIEW_NO_SPELL = "Kein Schadens-/Heilzauber in deinen Aktionsleisten gefunden",

	OPT_STAT_AVG = "Basis-Durchschnitt (Direkt + DoT/HoT)",
	OPT_STAT_WEIGHTED = "Gewichteter Durchschnitt (mit Krit-%)",
	OPT_STAT_RANGE = "Bereich (Min-Max)",
	OPT_STAT_CRIT = "Geschätzter kritischer Treffer",
	OPT_STAT_DPM = "Effizienz (DPM / HPM / DPR)",
	OPT_STAT_DPS = "DPS / HPS (nach Zauberzeit)",
	OPT_PREVIEW_AUTO = "Automatisch (1. Zauber der Leisten)",

	OPT_SHOW_DAMAGE = "Zentralen Wert anzeigen",
	OPT_SHOW_DAMAGE_TT = "Zeigt oder verbirgt den Wert in der Mitte der Aktionsbuttons.",
	OPT_CENTER_STAT = "Zentraler Wert",
	OPT_CENTER_STAT_TT = "Wähle aus, welcher Wert in der Mitte jedes Aktionsbuttons angezeigt wird.",
	OPT_CENTER_FONT_SIZE = "Schriftgröße (Mitte)",
	OPT_CENTER_FONT_SIZE_TT = "Passt die Schriftgröße in der Button-Mitte an.",
	OPT_SHOW_CASTS = "Verbleibende Zauber anzeigen",
	OPT_SHOW_CASTS_TT = "Zeigt unten rechts an, wie oft der Zauber mit deiner aktuellen Ressource gewirkt werden kann.",
	OPT_CASTS_FONT_SIZE = "Schriftgröße (Zauberzähler)",
	OPT_CASTS_FONT_SIZE_TT = "Passt die Schriftgröße des Zählers unten rechts an.",
	OPT_COMPACT_NUMBERS = "Große Zahlen abkürzen (1.4k)",
	OPT_COMPACT_NUMBERS_TT = "Kürzt Zahlen >= 1000 auf Buttons ab (z.B. 1450 -> 1.4k).",
	OPT_SHOW_TOOLTIP_STATS = "Detaillierte Werte im Tooltip anzeigen",
	OPT_SHOW_TOOLTIP_STATS_TT = "Fügt Durchschnitt, gewichteten Krit, DPM/HPM und DPS/HPS zu Zauber-Tooltips hinzu.",
	OPT_PREVIEW_SPELL = "Vorschau-Zauber",
	OPT_PREVIEW_SPELL_TT = "Wähle einen deiner Zauber für die Live-Vorschau unten.",
	OPT_COMBAT_LOCKED = "Optionen können im Kampf nicht geöffnet werden.",

	RES_MANA = "Mana",
	RES_RAGE = "Wut",
	RES_ENERGY = "Energie",
	RES_FOCUS = "Fokus",
	RES_GENERIC = "Ress.",
	WORD_HEALING = "Heilung",
	WORD_DAMAGE = "Schaden",
	TAG_CAST = "%.1fs Zauber",
	TAG_GCD = "%.2gs GCD",
	COMBO_PT_SINGULAR = " (%d Pkt.)",
	COMBO_PT_PLURAL = " (%d Pkt.)",

	TT_TOTAL_AVG = "%s gesamt (Ø)%s",
	TT_DIRECT_PERIODIC = "  Direkt / Periodisch",
	TT_TOTAL_DURATION = "%s gesamt (%gs)%s",
	TT_AVERAGE = "%s (Ø)%s",
	TT_CRIT = "Kritisch (%s)",
	TT_CRIT_TOTAL_FMT = "%.1f (gesamt %.1f)",
	TT_CRIT_MAX = "Max. Krit (%s)",
	TT_WEIGHTED_AVG = "Krit-gewichteter Ø",
	TT_PER_SEC_VALUE = "%.1f / Sek.",
	TT_PERIODIC_DPS = "%s periodisch (%gs)",
	TT_REMAINING_CASTS = "Verbleibende Zauber",
}

local parser = {
	thousandPattern = "(%d)[ %.](%d%d%d)",
	ignoreLineWords = { "sitzen", "hinsetzen" },

	healDetectPatterns = {
		"heilt[^%.]-%d+",
		"heilen[^%.]-%d+",
		"stellt[^%.]-%d+[^%.]-gesundheit",
		"%d+%s+gesundheit",
		"heilung",
	},
	damageDetectPatterns = {
		"%d+[^%.]-schaden",
		"waffenschaden",
	},

	healContextWords = { "heilt", "heilen", "heilung", "gesundheit" },
	damageContextWords = { "schaden", "fügt", "verursacht" },

	schoolPatterns = {
		{ school = 2, words = { "heiligschaden", "heilig" } },
		{ school = 3, words = { "feuerschaden", "feuer" } },
		{ school = 4, words = { "naturschaden", "natur" } },
		{ school = 5, words = { "frostschaden", "frost" } },
		{ school = 6, words = { "schattenschaden", "schatten" } },
		{ school = 7, words = { "arkanschaden", "arkan" } },
		{ school = 1, words = { "körperlichen schaden", "blutungsschaden", "waffenschaden", "körperlich" } },
	},

	chunkPatterns = {
		{ pattern = "(%d+)%s+bis%s+(%d+)[^%.]-schaden",  kind = "damage",    range = true },
		{ pattern = "heilt[^%d%.]*(%d+)%s+bis%s+(%d+)",  kind = "heal",      range = true,  requiresLineKind = "heal" },
		{ pattern = "um%s+(%d+)%s+bis%s+(%d+)",          kind = "heal",      range = true,  requiresLineKind = "heal" },
		{ pattern = "weitere%s+(%d+)%s+bis%s+(%d+)",     useLineKind = true, range = true },
		{ pattern = "(%d+[%.,]?%d*)%s+[^%d%.,]+schaden", kind = "damage",    range = false },
		{ pattern = "(%d+[%.,]?%d*)%s+schaden",          kind = "damage",    range = false },
		{ pattern = "waffenschaden[^%d]*plus%s+(%d+)",   kind = "damage",    range = false },
		{ pattern = "um%s+(%d+)%s+gesundheit",           kind = "heal",      range = false, requiresLineKind = "heal" },
		{ pattern = "(%d+)%s+gesundheit",                kind = "heal",      range = false, requiresLineKind = "heal" },
		{ pattern = "um%s+(%d+)[%s%p]",                  kind = "heal",      range = false, requiresLineKind = "heal" },
		{ pattern = "weitere%s+(%d+)",                   useLineKind = true, range = false },
	},

	comboHintWord = "combo",
	comboLinePatterns = {
		"^%s*(%d+)%s+punkte?%s*:%s*(.+)$",
	},
	comboRangePatterns = {
		"^(%d+)%s+bis%s+(%d+)",
		"^(%d+)%s*%-%s*(%d+)",
	},

	durationUnitPatterns = {
		{ pattern = "(%d)%s+sek%.?",    replacement = "%1 sec" },
		{ pattern = "(%d)%s+s([%s%p])", replacement = "%1 sec%2" },
	},
	intervalDurationPatterns = {
		"alle%s+([%d%.,]+)%s+sec.-([%d%.,]+)%s+sec%s+lang",
		"alle%s+([%d%.,]+)%s+sec.-über%s+([%d%.,]+)%s+sec",
	},
	perSecDurationPatterns = {
		"pro%s+sec.-([%d%.,]+)%s+sec%s+lang",
		"jede%s+sec.-([%d%.,]+)%s+sec%s+lang",
	},
	overDurationPatterns = {
		"^[^%.,%d]*über%s+([%d%.,]+)%s+sec",
	},
	forDurationPatterns = {
		"^([^%.,%d]*)im verlauf von%s+([%d%.,]+)%s+sec",
		"^([^%.,%d]*)([%d%.,]+)%s+sec%s+lang",
		"^([^%.,%d]*)für%s+([%d%.,]+)%s+sec",
	},
	beforeDurationPatterns = {
		"im verlauf von%s+([%d%.,]+)%s+sec[^%d]*$",
	},
	conjunctionWords = { "und", "sowie", "plus" },
}

ns.RegisterLocale("deDE", ui, parser)
