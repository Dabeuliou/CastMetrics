local _, ns = ...

if ns.LOCALE ~= "esES" then
	return
end

local ui = {
	HELP_HEADER = "Comandos disponibles:",
	HELP_CONFIG = "Abrir el panel de opciones",
	HELP_DMG = "Mostrar / ocultar la estadística central",
	HELP_CASTS = "Mostrar / ocultar los lanzamientos restantes",
	HELP_TOOLTIP = "Mostrar / ocultar las estadísticas en el tooltip",
	HELP_MODE = "Cambiar la estadística central (avg / weighted / range / crit / dpm / dps)",
	HELP_COMPACT = "Activar / desactivar el formato compacto (1.4k)",
	HELP_DEBUG = "Inspeccionar el tooltip de una ranura (o botón bajo el cursor)",

	CMD_CENTER_STAT = "Estadística central: %s",
	CMD_CASTS = "Lanzamientos restantes: %s",
	CMD_TOOLTIP = "Estadísticas en tooltip: %s",
	CMD_COMPACT = "Formato compacto: %s",
	STATE_ON = "ON",
	STATE_OFF = "OFF",

	DEBUG_HEADER = "Inspección %s=%s (Retail=%s, Locale=%s):",
	DEBUG_EMPTY_SLOT = "No hay acción en esta ranura.",
	DEBUG_NO_TOOLTIP = "C_TooltipInfo no devolvió datos utilizables.",
	DEBUG_NO_PARSER_MATCH = "Parser -> no se detectaron valores.",

	SPELL_FALLBACK_NAME = "Hechizo #%s",
	PREVIEW_HEADER = "Vista previa del botón (en vivo)",
	PREVIEW_HINT = "Pasa el cursor sobre el botón de ejemplo para ver también su tooltip enriquecido.",
	PREVIEW_NO_SPELL = "No se encontró ningún hechizo de daño/sanación en tus barras",

	OPT_STAT_AVG = "Media base (Directo + DoT/HoT)",
	OPT_STAT_WEIGHTED = "Media ponderada (con % crítico)",
	OPT_STAT_RANGE = "Rango (Mín-Máx)",
	OPT_STAT_CRIT = "Golpe crítico estimado",
	OPT_STAT_DPM = "Eficiencia (DPM / HPM / DPR)",
	OPT_STAT_DPS = "DPS / HPS (por tiempo de lanzamiento)",
	OPT_PREVIEW_AUTO = "Automático (1.er hechizo de las barras)",

	OPT_SHOW_DAMAGE = "Mostrar estadística central",
	OPT_SHOW_DAMAGE_TT = "Muestra u oculta el valor en el centro de los botones de acción.",
	OPT_CENTER_STAT = "Estadística central",
	OPT_CENTER_STAT_TT = "Elige la estadística que se muestra en el centro de cada botón de acción.",
	OPT_CENTER_FONT_SIZE = "Tamaño del texto central",
	OPT_CENTER_FONT_SIZE_TT = "Ajusta el tamaño de fuente en el centro del botón.",
	OPT_SHOW_CASTS = "Mostrar lanzamientos posibles",
	OPT_SHOW_CASTS_TT = "Muestra abajo a la derecha cuántas veces puedes lanzar el hechizo con tu recurso actual.",
	OPT_CASTS_FONT_SIZE = "Tamaño del contador de lanzamientos",
	OPT_CASTS_FONT_SIZE_TT = "Ajusta el tamaño de fuente del contador abajo a la derecha.",
	OPT_COMPACT_NUMBERS = "Formato corto para números grandes (1.4k)",
	OPT_COMPACT_NUMBERS_TT = "Abrevia los números >= 1000 en los botones (ej. 1450 -> 1.4k).",
	OPT_SHOW_TOOLTIP_STATS = "Mostrar estadísticas detalladas en el tooltip",
	OPT_SHOW_TOOLTIP_STATS_TT = "Añade media, media ponderada, DPM/HPM y DPS/HPS a los tooltips de hechizos.",
	OPT_PREVIEW_SPELL = "Hechizo de vista previa",
	OPT_PREVIEW_SPELL_TT = "Elige uno de tus hechizos para previsualizar tus ajustes abajo.",
	OPT_COMBAT_LOCKED = "No se pueden abrir las opciones en combate.",

	RES_MANA = "Maná",
	RES_RAGE = "Ira",
	RES_ENERGY = "Energía",
	RES_FOCUS = "Enfoque",
	RES_GENERIC = "Rec.",
	WORD_HEALING = "Sanación",
	WORD_DAMAGE = "Daño",
	TAG_CAST = "%.1fs lanz.",
	TAG_GCD = "%.2gs GCD",
	TAG_CD = "%s reutil.",
	COMBO_PT_SINGULAR = " (%d pto)",
	COMBO_PT_PLURAL = " (%d ptos)",

	TT_TOTAL_AVG = "%s total (media)%s",
	TT_DIRECT_PERIODIC = "  Directo / Periódico",
	TT_TOTAL_DURATION = "%s total (%gs)%s",
	TT_AVERAGE = "%s medio%s",
	TT_CRIT = "Crítico (%s)",
	TT_CRIT_TICK = "Crítico / tick (%s)",
	TT_WEIGHTED_AVG_PCT = "Media ponderada (%.1f%% crít.)",
	TT_PER_SEC_VALUE = "%.1f / s",
	TT_PER_GCD = "%s por GCD (%s)",
	TT_PERIODIC_DPS = "%s periódico (%gs)",
	TT_REMAINING_CASTS = "Lanzamientos posibles",
}

local parser = {
	thousandPattern = "(%d)[ %.](%d%d%d)",
	ignoreLineWords = { "sentado" },

	healDetectPatterns = {
		"sana[^%.]-%d+",
		"restaura[^%.]-%d+[^%.]-salud",
		"%d+[%.,]?%d*%s*%%[^%.]-salud",
		"%d+%s+p%.?%s+de%s+salud",
		"%d+%s+puntos?%s+de%s+salud",
		"sanación",
	},
	damageDetectPatterns = {
		"%d+%s+p%.?%s+de%s+daño",
		"%d+%s+puntos?%s+de%s+daño",
		"%d+[^%.]-daño",
		"daño de arma",
	},

	healContextWords = { "sana", "sanación", "salud" },
	damageContextWords = { "daño", "inflige" },

	schoolPatterns = {
		{ school = 2, words = { "sagrado" } },
		{ school = 3, words = { "de fuego", "fuego" } },
		{ school = 4, words = { "de naturaleza", "naturaleza" } },
		{ school = 5, words = { "de escarcha", "escarcha" } },
		{ school = 6, words = { "de las sombras", "sombras" } },
		{ school = 7, words = { "arcano" } },
		{ school = 1, words = { "físico", "sangrado", "daño de arma" } },
	},

	chunkPatterns = {
		{ pattern = "(%d+)%s+a%s+(%d+)%s+p%.?%s+de%s+daño", kind = "damage", range = true },
		{ pattern = "(%d+)%s+a%s+(%d+)%s+puntos?%s+de%s+daño", kind = "damage", range = true },
		{ pattern = "(%d+)%s+a%s+(%d+)%s+p%.?%s+de%s+salud", kind = "heal", range = true },
		{ pattern = "(%d+)%s+a%s+(%d+)%s+puntos?%s+de%s+salud", kind = "heal", range = true },
		{ pattern = "(%d+)%s+a%s+(%d+)%s+p%.?%s+más", useLineKind = true, range = true },
		{ pattern = "(%d+)%s+a%s+(%d+)%s+puntos?%s+adicionales", useLineKind = true, range = true },
		{ pattern = "(%d+)%s+a%s+(%d+)%s+adicionales", useLineKind = true, range = true },
		{ pattern = "(%d+[%.,]?%d*)%s+p%.?%s+de%s+daño", kind = "damage", range = false },
		{ pattern = "(%d+[%.,]?%d*)%s+puntos?%s+de%s+daño", kind = "damage", range = false },
		{ pattern = "daño de arma[^%d]*más%s+(%d+)", kind = "damage", range = false },
		{ pattern = "sana[^%d%%%.]*(%d+[%.,]?%d*)%s*%%%s+de%s+[^%.]-salud", kind = "heal", requiresLineKind = "heal", isHealthPct = true },
		{ pattern = "restaura[^%d%%%.]*(%d+[%.,]?%d*)%s*%%%s+de%s+[^%.]-salud", kind = "heal", requiresLineKind = "heal", isHealthPct = true },
		{ pattern = "un%s+(%d+[%.,]?%d*)%s*%%%s+de%s+[^%.]-salud", kind = "heal", requiresLineKind = "heal", isHealthPct = true },
		{ pattern = "(%d+[%.,]?%d*)%s+p%.?%s+de%s+salud", kind = "heal", range = false },
		{ pattern = "(%d+[%.,]?%d*)%s+puntos?%s+de%s+salud", kind = "heal", range = false },
		{ pattern = "(%d+[%.,]?%d*)%s+p%.?%s+más", useLineKind = true, range = false },
		{ pattern = "(%d+[%.,]?%d*)%s+puntos?%s+adicionales", useLineKind = true, range = false },
		{ pattern = "(%d+[%.,]?%d*)%s+adicionales", useLineKind = true, range = false },
		{ pattern = "(%d+[%.,]?%d*)%s+p%.", useLineKind = true, range = false },
		{ pattern = "sana[^%d%.]*(%d+[%.,]?%d*)%s+p%.", kind = "heal", range = false, requiresLineKind = "heal" },
		{ pattern = "sana[^%d%.]*(%d+)", kind = "heal", range = false, requiresLineKind = "heal" },
	},

	comboHintWord = "combo",
	comboLinePatterns = {
		"^%s*(%d+)%s+p%.?%s*:%s*(.+)$",
		"^%s*(%d+)%s+puntos?%s*:%s*(.+)$",
	},
	comboRangePatterns = {
		"^(%d+[%.,]?%d*)%s+a%s+(%d+[%.,]?%d*)",
		"^(%d+[%.,]?%d*)%s*%-%s*(%d+[%.,]?%d*)",
	},

	durationUnitPatterns = {
		{ pattern = "(%d)%s+seg%.?", replacement = "%1 sec" },
		{ pattern = "(%d)%s+s([%s%p])", replacement = "%1 sec%2" },
	},
	intervalDurationPatterns = {
		"cada%s+([%d%.,]+)%s+sec.-durante%s+([%d%.,]+)%s+sec",
	},
	perSecDurationPatterns = {
		"cada%s+sec.-durante%s+([%d%.,]+)%s+sec",
		"por%s+sec.-durante%s+([%d%.,]+)%s+sec",
	},
	overDurationPatterns = {
		"^[^%.,%d]*a lo largo de%s+([%d%.,]+)%s+sec",
		"^[^%.,%d]*en%s+([%d%.,]+)%s+sec",
	},
	forDurationPatterns = {
		"^([^%.,%d]*)durante%s+([%d%.,]+)%s+sec",
	},
	beforeDurationPatterns = {
		"durante%s+([%d%.,]+)%s+sec[^%d]*$",
	},
	cooldownSecPatterns = {
		"([%d%.,]+)%s+sec%s+de%s+reutilizaci",
		"([%d%.,]+)%s+sec%s+reutilizaci",
	},
	cooldownMinPatterns = {
		"([%d%.,]+)%s+min%s+de%s+reutilizaci",
		"([%d%.,]+)%s+min%s+reutilizaci",
	},
	conjunctionWords = { "y" },
}

ns.RegisterLocale("esES", ui, parser)
