local _, ns = ...

if ns.LOCALE ~= "frFR" then
	return
end

local ui = {
	HELP_HEADER = "Commandes disponibles :",
	HELP_CONFIG = "Ouvrir le panneau d'options graphique",
	HELP_DMG = "Afficher / masquer la stat centrale",
	HELP_CASTS = "Afficher / masquer le nombre de lancers (ressource)",
	HELP_TOOLTIP = "Afficher / masquer les stats (DPM, HPM, DPS) dans le tooltip",
	HELP_MODE = "Basculer la stat centrale (avg / weighted / range / crit / dpm / dps)",
	HELP_COMPACT = "Activer / désactiver le format court (1.4k)",
	HELP_DEBUG = "Inspecter le tooltip d'un slot (ou bouton survolé)",

	CMD_CENTER_STAT = "Stat centrale : %s",
	CMD_CASTS = "Nombre de casts : %s",
	CMD_TOOLTIP = "Stats dans le tooltip : %s",
	CMD_COMPACT = "Format compact : %s",
	STATE_ON = "ON",
	STATE_OFF = "OFF",

	DEBUG_HEADER = "Inspection %s=%s (Retail=%s, Locale=%s) :",
	DEBUG_EMPTY_SLOT = "Aucune action dans ce slot.",
	DEBUG_NO_TOOLTIP = "C_TooltipInfo n'a retourné aucune donnée exploitable.",
	DEBUG_NO_PARSER_MATCH = "Parser -> aucune valeur détectée.",

	SPELL_FALLBACK_NAME = "Sort #%s",
	PREVIEW_HEADER = "Aperçu du bouton (en direct)",
	PREVIEW_HINT = "Survolez le bouton d'exemple pour inspecter aussi son tooltip enrichi.",
	PREVIEW_NO_SPELL = "Aucun sort de dégâts/soins trouvé sur vos barres",

	OPT_STAT_AVG = "Moyenne de base (Direct + DoT/HoT)",
	OPT_STAT_WEIGHTED = "Moyenne pondérée (avec % critique)",
	OPT_STAT_RANGE = "Intervalle (Min-Max)",
	OPT_STAT_CRIT = "Coup critique estimé",
	OPT_STAT_DPM = "Efficacité (DPM / HPM / DPR)",
	OPT_STAT_DPS = "DPS / HPS (par temps de cast)",
	OPT_PREVIEW_AUTO = "Automatique (1er sort des barres)",

	OPT_SHOW_DAMAGE = "Afficher la stat centrale",
	OPT_SHOW_DAMAGE_TT = "Affiche ou masque la valeur affichée au centre des boutons d'action.",
	OPT_CENTER_STAT = "Statistique centrale",
	OPT_CENTER_STAT_TT = "Choisissez la statistique affichée au milieu de chaque bouton d'action.",
	OPT_CENTER_FONT_SIZE = "Taille du texte central",
	OPT_CENTER_FONT_SIZE_TT = "Ajuste la taille de la police au centre du bouton (pratique pour lire un gros DPM ou DPS).",
	OPT_SHOW_CASTS = "Afficher les lancers possibles",
	OPT_SHOW_CASTS_TT = "Affiche en bas à droite combien de fois vous pouvez lancer le sort avec votre ressource actuelle.",
	OPT_CASTS_FONT_SIZE = "Taille du compteur de lancers",
	OPT_CASTS_FONT_SIZE_TT = "Ajuste la taille de la police du compteur en bas à droite du bouton.",
	OPT_COMPACT_NUMBERS = "Format court des grands nombres (1.4k)",
	OPT_COMPACT_NUMBERS_TT = "Abrège les nombres >= 1000 sur les boutons (ex: 1450 -> 1.4k).",
	OPT_SHOW_TOOLTIP_STATS = "Afficher les stats détaillées dans le tooltip",
	OPT_SHOW_TOOLTIP_STATS_TT = "Ajoute la moyenne, le critique pondéré, le DPM/HPM et le DPS/HPS dans les info-bulles des sorts.",
	OPT_PREVIEW_SPELL = "Sort d'aperçu",
	OPT_PREVIEW_SPELL_TT = "Choisissez un de vos sorts pour prévisualiser vos réglages sur le bouton d'exemple ci-dessous.",
	OPT_COMBAT_LOCKED = "Impossible d'ouvrir les options en combat.",

	RES_MANA = "Mana",
	RES_RAGE = "Rage",
	RES_ENERGY = "Énergie",
	RES_FOCUS = "Focalisation",
	RES_GENERIC = "Ress.",
	WORD_HEALING = "Soins",
	WORD_DAMAGE = "Dégâts",
	TAG_CAST = "%.1fs cast",
	TAG_GCD = "%.2gs GCD",
	COMBO_PT_SINGULAR = " (%d pt)",
	COMBO_PT_PLURAL = " (%d pts)",

	TT_TOTAL_AVG = "%s totaux (moy.)%s",
	TT_DIRECT_PERIODIC = "  Direct / Périodique",
	TT_TOTAL_DURATION = "%s totaux (%gs)%s",
	TT_AVERAGE = "%s moyens%s",
	TT_CRIT = "Critique (%s)",
	TT_CRIT_TOTAL_FMT = "%.1f (total %.1f)",
	TT_CRIT_MAX = "Critique max (%s)",
	TT_WEIGHTED_AVG = "Moyenne pondérée (crit)",
	TT_PER_SEC_VALUE = "%.1f / s",
	TT_PERIODIC_DPS = "%s périodique (%gs)",
	TT_REMAINING_CASTS = "Lancers possibles",
}

local parser = {
	thousandPattern = "(%d)[ ,](%d%d%d)",
	ignoreLineWords = { "assis" },

	healDetectPatterns = {
		"%d+%s+points?%s+de%s+vie",
		"soigne",
		"soins",
	},
	damageDetectPatterns = {
		"%d+%s+points?%s+de%s+dégât",
		"%d+%s+points?%s+de%s+degat",
		"dégâts? de l'arme",
	},

	healContextWords = { "soigne", "soins", "points?%s+de%s+vie" },
	damageContextWords = { "dégât", "degat", "inflige" },

	schoolPatterns = {
		{ school = 2, words = { "du sacré", "sacré" } },
		{ school = 3, words = { "de feu" } },
		{ school = 4, words = { "de nature" } },
		{ school = 5, words = { "de givre" } },
		{ school = 6, words = { "d'ombre" } },
		{ school = 7, words = { "des arcanes" } },
		{ school = 1, words = { "physique", "saignement", "de l'arme" } },
	},

	chunkPatterns = {
		{ pattern = "(%d+)%s+à%s+(%d+)%s+points?%s+de%s+dégâts?", kind = "damage", range = true },
		{ pattern = "(%d+)%s+à%s+(%d+)%s+points?%s+de%s+degats?", kind = "damage", range = true },
		{ pattern = "(%d+)%s+à%s+(%d+)%s+points?%s+de%s+vie", kind = "heal", range = true },
		{ pattern = "(%d+)%s+à%s+(%d+)%s+points?%s+supplémentaires", useLineKind = true, range = true },
		{ pattern = "(%d+)%s+à%s+(%d+)%s+supplémentaires", useLineKind = true, range = true },
		{ pattern = "soigne[^%d%.]*(%d+)%s+à%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
		{ pattern = "pour%s+(%d+)%s+à%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
		{ pattern = "(%d+)%s+points?%s+de%s+dégâts?", kind = "damage", range = false },
		{ pattern = "(%d+)%s+points?%s+de%s+degats?", kind = "damage", range = false },
		{ pattern = "dégâts? de l'arme[^%d]*plus%s+(%d+)", kind = "damage", range = false },
		{ pattern = "(%d+)%s+points?%s+de%s+vie", kind = "heal", range = false },
		{ pattern = "(%d+)%s+points?%s+supplémentaires", useLineKind = true, range = false },
		{ pattern = "(%d+)%s+supplémentaires", useLineKind = true, range = false },
		{ pattern = "pour%s+(%d+)%s+points?", kind = "heal", range = false, requiresLineKind = "heal" },
		{ pattern = "soigne[^%d%.]*(%d+)", kind = "heal", range = false, requiresLineKind = "heal" },
	},

	comboHintWord = "combo",
	comboLinePatterns = {
		"^%s*(%d+)%s+points?%s*:%s*(.+)$",
	},
	comboRangePatterns = {
		"^(%d+)%s+à%s+(%d+)",
		"^(%d+)%s*%-%s*(%d+)",
	},

	durationUnitPatterns = {
		{ pattern = "(%d)%s+s([%s%p])", replacement = "%1 sec%2" },
	},
	intervalDurationPatterns = {
		"toutes les%s+([%d%.,]+)%s+sec.-pendant%s+([%d%.,]+)%s+sec",
	},
	perSecDurationPatterns = {
		"toutes les%s+sec.-pendant%s+([%d%.,]+)%s+sec",
		"par sec.-pendant%s+([%d%.,]+)%s+sec",
	},
	overDurationPatterns = {
		"^[^%.,%d]*en%s+([%d%.,]+)%s+sec",
	},
	forDurationPatterns = {
		"^([^%.,%d]*)pendant%s+([%d%.,]+)%s+sec",
	},
	beforeDurationPatterns = {
		"en%s+([%d%.,]+)%s+sec[^%d]*$",
	},
	conjunctionWords = { "et" },
}

ns.RegisterLocale("frFR", ui, parser)
