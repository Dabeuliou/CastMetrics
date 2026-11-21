-- En Lua dans WoW, chaque fichier listé dans le .toc reçoit en arguments (...) :
--   1) le nom du dossier de l'addon (addonName)
--   2) une table partagée privée entre tous les fichiers de l'addon (ns = namespace)
local addonName, ns = ...

-- Valeurs par défaut de la configuration sauvegardée (SavedVariables)
local DEFAULT_DB = {
	showDamage = true,
	centerStat = "avg", -- "avg", "weighted", "range", "crit", "dpm", "dps"
	centerFontSize = 11,
	showCasts = true,
	castsFontSize = 10,
	showTooltipStats = true,
	compactNumbers = true, -- ex: 1450 -> 1.4k
	previewSpellID = 0, -- 0 = sélection automatique du premier sort trouvé sur les barres
}

-- Détection Retail (Mainline) vs WoW Forever / Classic+ (multiplicateurs critiques, DoTs, Hâte)
ns.IS_RETAIL = (WOW_PROJECT_ID ~= nil and WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

-- Vérifie si une valeur est protégée ("secret value") par le client moderne (Retail 12.x / Forever 16001)
function ns.IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- Formate un nombre pour qu'il reste lisible sur un petit bouton d'action
function ns.FormatNumber(value)
	if not value or ns.IsSecret(value) then
		return ""
	end

	local db = CastMetricsDB
	if db and db.compactNumbers and value >= 1000 then
		return string.format("%.1fk", value / 1000)
	end

	return tostring(math.floor(value + 0.5))
end

-- Copie récursivement ou simplement les clés manquantes depuis src vers dst
local function ApplyDefaults(dst, src)
	for key, defaultValue in pairs(src) do
		if dst[key] == nil then
			dst[key] = defaultValue
		end
	end
end

local function PrintHelp()
	print("|cff00ccff[CastMetrics]|r Commandes disponibles :")
	print("  |cffffd100/cm config|r - Ouvrir le panneau d'options graphique")
	print("  |cffffd100/cm dmg|r - Afficher / masquer la stat centrale")
	print("  |cffffd100/cm casts|r - Afficher / masquer le nombre de lancers (ressource)")
	print("  |cffffd100/cm tooltip|r - Afficher / masquer les stats (DPM, HPM, DPS) dans le tooltip")
	print("  |cffffd100/cm mode|r - Basculer la stat centrale (avg / weighted / range / crit / dpm / dps)")
	print("  |cffffd100/cm compact|r - Activer / désactiver le format court (1.4k)")
	print("  |cffffd100/cm debug [slot]|r - Inspecter le tooltip d'un slot (ou bouton survolé)")
end

local function GetHoveredAction()
	-- Client moderne : GetMouseFoci() renvoie une liste de frames sous le curseur (y compris Bartender4 / ElvUI)
	if GetMouseFoci then
		local foci = GetMouseFoci()
		if foci then
			for _, frame in ipairs(foci) do
				if ns.GetButtonAction then
					local kind, value = ns.GetButtonAction(frame)
					if kind then
						return kind, value
					end
				elseif frame.action and type(frame.action) == "number" and not ns.IsSecret(frame.action) then
					return "action", frame.action
				end
			end
		end
	elseif GetMouseFocus then
		local frame = GetMouseFocus()
		if frame then
			if ns.GetButtonAction then
				local kind, value = ns.GetButtonAction(frame)
				if kind then
					return kind, value
				end
			elseif frame.action and type(frame.action) == "number" and not ns.IsSecret(frame.action) then
				return "action", frame.action
			end
		end
	end
	return "action", 1
end

local function RunDebug(slotArg)
	local actionKind, actionValue
	local explicitSlot = tonumber(slotArg)
	if explicitSlot then
		actionKind, actionValue = "action", explicitSlot
	else
		actionKind, actionValue = GetHoveredAction()
	end

	print(string.format("|cff00ccff[CastMetrics Debug]|r Inspection %s=%s (Retail=%s) :", tostring(actionKind), tostring(actionValue), tostring(ns.IS_RETAIL)))

	if actionKind == "action" then
		if not HasAction(actionValue) then
			print("  Aucune action dans ce slot.")
			return
		end

		local actionType, id = GetActionInfo(actionValue)
		print(string.format("  GetActionInfo: type=%s, id=%s", tostring(actionType), tostring(id)))
	end

	local tooltipData = (actionKind == "action")
			and (C_TooltipInfo and C_TooltipInfo.GetAction(actionValue))
		or (C_TooltipInfo and C_TooltipInfo.GetSpellByID and C_TooltipInfo.GetSpellByID(actionValue))
	if tooltipData and not ns.IsSecret(tooltipData) and tooltipData.lines and not ns.IsSecret(tooltipData.lines) then
		local tid = (tooltipData.id and not ns.IsSecret(tooltipData.id)) and tostring(tooltipData.id) or "<secret>"
		print(string.format("  tooltipData.id=%s, lignes=%d", tid, #tooltipData.lines))
		for i, line in ipairs(tooltipData.lines) do
			if line and not ns.IsSecret(line) then
				local left = (line.leftText and not ns.IsSecret(line.leftText)) and line.leftText or "<secret>"
				local right = (line.rightText and not ns.IsSecret(line.rightText)) and line.rightText or ""
				print(string.format("  [%d] %s | %s", i, left, right))
			end
		end
	else
		print("  C_TooltipInfo n'a retourné aucune donnée exploitable.")
	end

	local parsed, spellID
	if actionKind == "action" then
		parsed, spellID = ns.TooltipParser.GetActionValues(actionValue)
	else
		parsed, spellID = ns.TooltipParser.GetSpellValues(actionValue)
		spellID = spellID or actionValue
	end
	if parsed then
		print(string.format("  Parser -> kind=%s, min=%d, max=%d, avg=%d", parsed.kind, parsed.min, parsed.max, parsed.avg))
	else
		print("  Parser -> aucune valeur détectée.")
	end

	local casts, cost, powerType, isSecret
	if actionKind == "action" then
		casts, cost, powerType, isSecret = ns.ManaCalc.GetRemainingCasts(actionValue, spellID)
	else
		casts, cost, powerType, isSecret = ns.ManaCalc.GetRemainingCastsForSpell(spellID)
	end
	local castsStr = isSecret and (casts ~= nil and "<secret-curve>" or "nil") or tostring(casts)
	print(string.format(
		"  ManaCalc -> spellID=%s, cost=%s, powerType=%s, casts=%s, secret=%s",
		tostring(spellID),
		tostring(cost),
		tostring(powerType),
		castsStr,
		tostring(isSecret)
	))
	local db = CastMetricsDB
	if db then
		print(string.format("  Options -> showDamage=%s, showCasts=%s, centerStat=%s", tostring(db.showDamage), tostring(db.showCasts), tostring(db.centerStat)))
	end
end

-- Gestionnaire des commandes slash (/cm ou /castmetrics)
SLASH_CASTMETRICS1 = "/cm"
SLASH_CASTMETRICS2 = "/castmetrics"

SlashCmdList["CASTMETRICS"] = function(msg)
	-- string.match avec %S+ extrait les mots séparés par des espaces
	local cmd, arg = msg:lower():match("^%s*(%S+)%s*(.-)%s*$")
	local db = CastMetricsDB

	if cmd == "config" or cmd == "options" then
		if ns.OpenOptions then
			ns.OpenOptions()
		end
	elseif cmd == "dmg" then
		db.showDamage = not db.showDamage
		print("|cff00ccff[CastMetrics]|r Stat centrale : " .. (db.showDamage and "ON" or "OFF"))
		ns.RequestUpdate(false)
	elseif cmd == "casts" then
		db.showCasts = not db.showCasts
		print("|cff00ccff[CastMetrics]|r Nombre de casts : " .. (db.showCasts and "ON" or "OFF"))
		ns.RequestUpdate(true)
	elseif cmd == "tooltip" then
		db.showTooltipStats = not db.showTooltipStats
		print("|cff00ccff[CastMetrics]|r Stats dans le tooltip : " .. (db.showTooltipStats and "ON" or "OFF"))
	elseif cmd == "mode" then
		local order = { "avg", "weighted", "range", "crit", "dpm", "dps" }
		local nextStat = order[1]
		for i, statKey in ipairs(order) do
			if db.centerStat == statKey then
				nextStat = order[(i % #order) + 1]
				break
			end
		end
		db.centerStat = nextStat
		print("|cff00ccff[CastMetrics]|r Stat centrale : " .. db.centerStat)
		ns.RequestUpdate(false)
	elseif cmd == "compact" then
		db.compactNumbers = not db.compactNumbers
		print("|cff00ccff[CastMetrics]|r Format compact : " .. (db.compactNumbers and "ON" or "OFF"))
		ns.RequestUpdate(false)
	elseif cmd == "debug" then
		RunDebug(arg)
	else
		PrintHelp()
	end
end

-- Coalesce / anti-rebond : évite de recalculer 50 fois par seconde si plusieurs événements tombent ensemble
local pendingFullUpdate = false
local pendingManaUpdate = false
local timerScheduled = false

local function FlushUpdates()
	timerScheduled = false
	local full = pendingFullUpdate
	local manaOnly = pendingManaUpdate and not full
	pendingFullUpdate = false
	pendingManaUpdate = false

	if ns.UpdateAllButtons then
		ns.UpdateAllButtons(manaOnly)
	end
	if ns.RefreshOptionsPreview then
		ns.RefreshOptionsPreview()
	end
end

function ns.RequestUpdate(onlyMana)
	if onlyMana then
		pendingManaUpdate = true
	else
		pendingFullUpdate = true
	end

	if not timerScheduled then
		timerScheduled = true
		C_Timer.After(0.05, FlushUpdates)
	end
end

-- Table de dispatch des événements WoW (idiome Lua très courant et lisible)
local events = {}

function events.ADDON_LOADED(loadedAddon)
	if loadedAddon ~= addonName then
		return
	end

	-- Initialisation explicite recommandée sur Retail / WoW Forever
	CastMetricsDB = CastMetricsDB or {}
	if CastMetricsDB.centerStat == nil and CastMetricsDB.displayMode ~= nil then
		CastMetricsDB.centerStat = CastMetricsDB.displayMode
	end
	ApplyDefaults(CastMetricsDB, DEFAULT_DB)

	if ns.InitOptions then
		ns.InitOptions()
	end
	if ns.InitButtonOverlays then
		ns.InitButtonOverlays()
	end
end

function events.PLAYER_ENTERING_WORLD()
	if ns.InitButtonOverlays then
		ns.InitButtonOverlays()
	end
	if ns.ManaCalc and ns.ManaCalc.CacheMaxPowers then
		ns.ManaCalc.CacheMaxPowers()
	end
	ns.RequestUpdate(false)
end

function events.ACTIONBAR_SLOT_CHANGED()
	ns.RequestUpdate(false)
end

function events.ACTIONBAR_PAGE_CHANGED()
	ns.RequestUpdate(false)
end

function events.UPDATE_BONUS_ACTIONBAR()
	ns.RequestUpdate(false)
end

function events.UPDATE_SHAPESHIFT_FORM()
	if ns.ManaCalc and ns.ManaCalc.CacheMaxPowers then
		ns.ManaCalc.CacheMaxPowers()
	end
	ns.RequestUpdate(false)
end

function events.ACTIONBAR_UPDATE_STATE()
	ns.RequestUpdate(false)
end

function events.SPELLS_CHANGED()
	ns.RequestUpdate(false)
end

function events.PLAYER_EQUIPMENT_CHANGED()
	ns.RequestUpdate(false)
end

function events.UNIT_AURA(unitTarget)
	if unitTarget == "player" then
		ns.RequestUpdate(false)
	end
end

function events.UNIT_POWER_UPDATE(unitTarget)
	if unitTarget == "player" then
		ns.RequestUpdate(true)
	end
end

function events.UNIT_MAXPOWER(unitTarget)
	if unitTarget == "player" then
		if ns.ManaCalc and ns.ManaCalc.CacheMaxPowers then
			ns.ManaCalc.CacheMaxPowers()
		end
		ns.RequestUpdate(true)
	end
end

-- Frame invisible dédiée uniquement à l'écoute des événements
local eventFrame = CreateFrame("Frame")
for eventName in pairs(events) do
	eventFrame:RegisterEvent(eventName)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local handler = events[event]
	if handler then
		handler(...)
	end
end)
