local _, ns = ...

-- Table associant chaque bouton d'action à ses FontStrings et à son cache :
-- overlays[button] = { dmgText = FontString, castsText = FontString, actionKey = string, spellID = number }
local overlays = {}
local hookedLibs = {}
local hookedCooldowns = {}

local GCD_MAX_DURATION = 1.55

-- Préfixes standards des barres d'action Blizzard (fallback si certains boutons ne sont pas dans ActionBarButtonEventsFrame)
local BAR_PREFIXES = {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarRightButton",
	"MultiBarLeftButton",
	"MultiBar5Button",
	"MultiBar6Button",
	"MultiBar7Button",
}

-- Bibliothèques LibActionButton utilisées par Bartender4, ElvUI, etc.
local LAB_LIBRARIES = {
	"LibActionButton-1.0",
	"LibActionButton-1.0-ElvUI",
}

local function ApplyFontSize(fs, fontSize)
	local fontPath = GameFontNormalSmall and GameFontNormalSmall:GetFont()
	if fontPath then
		fs:SetFont(fontPath, fontSize or 10, "OUTLINE")
	end
end

local function CreateOverlayFontString(parentFrame, anchorPoint, xOffset, yOffset, fontSize)
	local fs = parentFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	ApplyFontSize(fs, fontSize)

	-- En WoW moderne, SetJustifyH("RIGHT") sans largeur définie peut rendre le texte invisible.
	-- On donne donc deux ancres horizontales (gauche + droite) pour les coins alignés à droite.
	if anchorPoint == "BOTTOMRIGHT" then
		fs:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", 2, yOffset)
		fs:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", xOffset, yOffset)
		fs:SetJustifyH("RIGHT")
	else
		fs:SetPoint(anchorPoint, parentFrame, anchorPoint, xOffset, yOffset)
		fs:SetJustifyH("CENTER")
	end

	return fs
end

ns.ApplyFontSize = ApplyFontSize
ns.CreateOverlayFontString = CreateOverlayFontString

local function FormatCenterStat(parsed, spellID, db)
	if not parsed then
		return "", 1, 0.82, 0.2
	end

	local stat = db.centerStat or "avg"
	local isHeal = (parsed.kind == "heal")
	local r, g, b = isHeal and 0.3 or 1, isHeal and 1 or 0.82, isHeal and 0.45 or 0.2

	if stat == "range" then
		if parsed.min ~= parsed.max then
			return ns.FormatNumber(parsed.min) .. "-" .. ns.FormatNumber(parsed.max), r, g, b
		end
		return ns.FormatNumber(parsed.avg), r, g, b
	elseif stat == "avg" then
		return ns.FormatNumber(parsed.avg), r, g, b
	end

	local metrics = ns.TooltipStats and ns.TooltipStats.ComputeMetrics and ns.TooltipStats.ComputeMetrics(parsed, spellID)
	if not metrics then
		return ns.FormatNumber(parsed.avg), r, g, b
	end

	if stat == "weighted" then
		return ns.FormatNumber(metrics.weightedAvg), r, g, b
	elseif stat == "crit" then
		local val = metrics.critDirect or metrics.critTick
		if not val then
			return "", r, g, b
		end
		return ns.FormatNumber(val), 1, 0.95, 0.55
	elseif stat == "dpm" then
		if not metrics.dpm then
			return "", r, g, b
		end
		local text = (metrics.dpm >= 10) and string.format("%.1f", metrics.dpm) or string.format("%.2f", metrics.dpm)
		return text, 0.4, 0.85, 1
	elseif stat == "dps" then
		if not metrics.dps then
			return "", r, g, b
		end
		local text = (metrics.dps >= 100) and ns.FormatNumber(metrics.dps) or string.format("%.1f", metrics.dps)
		return text, 1, 0.65, 0.25
	end

	return ns.FormatNumber(parsed.avg), r, g, b
end

ns.FormatCenterStat = FormatCenterStat

local function ApplyCastsColor(fs, casts)
	if casts <= 0 then
		fs:SetTextColor(1, 0.25, 0.25) -- Rouge : plus assez de mana
	elseif casts == 1 then
		fs:SetTextColor(1, 0.5, 0.15) -- Orange : dernier lancer
	elseif casts <= 4 then
		fs:SetTextColor(1, 0.85, 0.2) -- Jaune : mana faible
	else
		fs:SetTextColor(0.4, 0.85, 1) -- Bleu clair : confortable
	end
end

local function RenderCastsText(overlay, casts, isSecret, secretColor, allowStale)
	if casts ~= nil then
		if isSecret then
			-- SetFormattedText accepte les valeurs secrètes côté C++ (sans conversion tostring en Lua)
			overlay.castsText:SetFormattedText("%d", casts)
			if secretColor and not ns.IsSecret(secretColor) and secretColor.GetRGBA then
				local r, g, b, a = secretColor:GetRGBA()
				overlay.castsText:SetTextColor(r, g, b, a)
			else
				overlay.castsText:SetTextColor(0.4, 0.85, 1)
			end
		else
			overlay.lastCasts = casts
			overlay.castsText:SetText(tostring(casts))
			ApplyCastsColor(overlay.castsText, casts)
		end
	elseif isSecret and allowStale and overlay.lastCasts ~= nil then
		overlay.castsText:SetText(tostring(overlay.lastCasts))
		ApplyCastsColor(overlay.castsText, overlay.lastCasts)
	else
		overlay.lastCasts = nil
		overlay.castsText:SetText("")
	end
end

ns.RenderCastsText = RenderCastsText

-- Résout l'action portée par un bouton Blizzard (button.action) ou LibActionButton (Bartender4, ElvUI)
function ns.GetButtonAction(button)
	if not button then
		return nil, nil
	end

	-- 1. Boutons LibActionButton-1.0 (Bartender4, ElvUI, etc.)
	if button.GetAction then
		local ok, actionType, actionValue = pcall(button.GetAction, button)
		if ok and not ns.IsSecret(actionType) and not ns.IsSecret(actionValue) then
			if actionType == "action" and type(actionValue) == "number" then
				return "action", actionValue
			elseif actionType == "spell" and type(actionValue) == "number" then
				return "spell", actionValue
			elseif actionType == "macro" and actionValue ~= nil and GetMacroSpell then
				local macroSpellID = GetMacroSpell(actionValue)
				if macroSpellID and not ns.IsSecret(macroSpellID) then
					return "spell", macroSpellID
				end
			end
			return nil, nil
		end
	end

	-- 2. Fallback sur l'état interne LibActionButton (_state_type / _state_action)
	if button._state_type and not ns.IsSecret(button._state_type) and not ns.IsSecret(button._state_action) then
		if button._state_type == "action" and type(button._state_action) == "number" then
			return "action", button._state_action
		elseif button._state_type == "spell" and type(button._state_action) == "number" then
			return "spell", button._state_action
		end
	end

	-- 3. Boutons Blizzard natifs (et Dominos)
	local slot = button.action
	if slot and not ns.IsSecret(slot) and type(slot) == "number" then
		return "action", slot
	end

	return nil, nil
end

local function ApplyCooldownVisibility(overlay)
	if not overlay or not overlay.dmgText then
		return
	end

	local db = CastMetricsDB
	if not db or not db.hideOnCooldown or not db.showDamage or not overlay.parsed then
		overlay.dmgText:SetAlpha(1)
		return
	end

	local actionKind = overlay.actionKind
	local actionValue = overlay.actionValue
	local spellID = overlay.resolvedSpellID or overlay.spellID

	-- 1. Sur Retail moderne, isOnGCD est un booléen NeverSecret : on ne masque jamais pour le GCD seul
	local spellCDInfo = nil
	if spellID and C_Spell and C_Spell.GetSpellCooldown then
		local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
		if ok and info and not ns.IsSecret(info) then
			spellCDInfo = info
			if info.isOnGCD == true then
				overlay.dmgText:SetAlpha(1)
				return
			end
		end
	end

	-- 2. Retail 12.x : DurationObject + SetAlphaFromBoolean (sûr même avec des secret values en combat)
	if overlay.dmgText.SetAlphaFromBoolean then
		local durationObj = nil
		if actionKind == "action" and actionValue and C_ActionBar and C_ActionBar.GetActionCooldownDuration then
			local ok, obj = pcall(C_ActionBar.GetActionCooldownDuration, actionValue, true)
			if not ok then
				ok, obj = pcall(C_ActionBar.GetActionCooldownDuration, actionValue)
			end
			if ok and obj then
				durationObj = obj
			end
		elseif spellID and C_Spell and C_Spell.GetSpellCooldownDuration then
			local ok, obj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
			if ok and obj then
				durationObj = obj
			end
		end

		if durationObj and durationObj.IsZero then
			local okZero, isZero = pcall(durationObj.IsZero, durationObj)
			if okZero and isZero ~= nil then
				overlay.dmgText:SetAlphaFromBoolean(isZero, 1, 0)
				return
			end
		end
	end

	-- 3. Fallback Classic / Forever (16001) et valeurs non-secrètes
	local startTime, duration, enabled
	if actionKind == "action" and actionValue then
		local getActionCD = (C_ActionBar and C_ActionBar.GetActionCooldown) or GetActionCooldown
		if getActionCD then
			local ok, s, d, e = pcall(getActionCD, actionValue)
			if ok then
				startTime, duration, enabled = s, d, e
			end
		end
	end
	if (startTime == nil or duration == nil) and spellCDInfo then
		startTime = spellCDInfo.startTime
		duration = spellCDInfo.duration
		enabled = spellCDInfo.isEnabled
	elseif (startTime == nil or duration == nil) and spellID and GetSpellCooldown then
		local ok, s, d, e = pcall(GetSpellCooldown, spellID)
		if ok then
			startTime, duration, enabled = s, d, e
		end
	end

	if startTime ~= nil and duration ~= nil and not ns.IsSecret(startTime) and not ns.IsSecret(duration) then
		local isEnabled = (enabled == nil or ns.IsSecret(enabled) or (enabled ~= 0 and enabled ~= false))
		if isEnabled and startTime > 0 and duration > GCD_MAX_DURATION then
			local remaining = (startTime + duration) - GetTime()
			if remaining > 0.05 then
				overlay.dmgText:SetAlpha(0)
				return
			end
		end
	end

	overlay.dmgText:SetAlpha(1)
end

local function ClearOverlay(overlay)
	overlay.dmgText:SetText("")
	overlay.dmgText:SetAlpha(1)
	overlay.castsText:SetText("")
	overlay.actionKey = nil
	overlay.actionKind = nil
	overlay.actionValue = nil
	overlay.spellID = nil
	overlay.resolvedSpellID = nil
	overlay.parsed = nil
	overlay.lastCasts = nil
end

local function UpdateButton(button, onlyMana)
	local overlay = overlays[button]
	if not overlay then
		return
	end

	if button.IsVisible and not button:IsVisible() then
		return
	end

	local actionKind, actionValue = ns.GetButtonAction(button)
	local isValidAction = (actionKind == "action" and HasAction(actionValue)) or (actionKind == "spell" and actionValue)
	if not isValidAction then
		if overlay.actionKey ~= nil then
			ClearOverlay(overlay)
		end
		return
	end

	local db = CastMetricsDB
	if not db then
		return
	end

	-- Maintient le conteneur au-dessus du bouton (utile si Bartender4/Masque ajuste le FrameLevel)
	local targetLevel = (button:GetFrameLevel() or 1) + 5
	if overlay.container:GetFrameLevel() < targetLevel then
		overlay.container:SetFrameLevel(targetLevel)
	end

	-- Si seule la mana/ressource a changé et que l'action est identique, on évite de re-parser le tooltip
	local actionKey = actionKind .. ":" .. tostring(actionValue)
	local sameAction = (overlay.actionKey == actionKey)
	local needTooltip = (not onlyMana) or (not sameAction)
	if needTooltip then
		overlay.actionKey = actionKey
		local parsed, spellID, hadSecret
		if actionKind == "action" then
			parsed, spellID, hadSecret = ns.TooltipParser.GetActionValues(actionValue)
		else
			parsed, spellID, hadSecret = ns.TooltipParser.GetSpellValues(actionValue)
			spellID = spellID or actionValue
		end
		-- En combat, si le tooltip devient "secret", on conserve la dernière valeur connue pour la même action
		if not hadSecret or not sameAction then
			overlay.parsed = parsed
		end
		if spellID then
			overlay.spellID = spellID
		elseif not sameAction then
			overlay.spellID = nil
		end
	end

	local resolvedID = overlay.spellID
	if actionKind == "action" and ns.ManaCalc and ns.ManaCalc.ResolveSpellID then
		resolvedID = ns.ManaCalc.ResolveSpellID(actionValue, overlay.spellID) or overlay.spellID
	end
	overlay.actionKind = actionKind
	overlay.actionValue = actionValue
	overlay.resolvedSpellID = resolvedID

	local activeParsed = overlay.parsed
	if activeParsed and activeParsed.comboTiers and ns.TooltipParser and ns.TooltipParser.ResolveComboTier then
		activeParsed = ns.TooltipParser.ResolveComboTier(activeParsed, false)
	end

	-- 1. Affichage de la stat centrale choisie dans les options
	if db.showDamage and activeParsed then
		local text, r, g, b = FormatCenterStat(activeParsed, resolvedID, db)
		overlay.dmgText:SetText(text)
		overlay.dmgText:SetTextColor(r, g, b)
		ApplyCooldownVisibility(overlay)
	else
		overlay.dmgText:SetText("")
		overlay.dmgText:SetAlpha(1)
	end

	-- 2. Affichage du nombre de lancers possibles avec la ressource actuelle
	if db.showCasts then
		local casts, _, _, isSecret, secretColor
		if actionKind == "action" then
			casts, _, _, isSecret, secretColor = ns.ManaCalc.GetRemainingCasts(actionValue, overlay.spellID)
		else
			casts, _, _, isSecret, secretColor = ns.ManaCalc.GetRemainingCastsForSpell(resolvedID)
		end
		RenderCastsText(overlay, casts, isSecret, secretColor, sameAction)
	else
		overlay.lastCasts = nil
		overlay.castsText:SetText("")
	end
end

local function UpdateButtonSmart(button)
	local overlay = overlays[button]
	if not overlay then
		return
	end
	if button.IsVisible and not button:IsVisible() then
		return
	end

	local actionKind, actionValue = ns.GetButtonAction(button)
	if not actionKind then
		if overlay.actionKey ~= nil then
			ClearOverlay(overlay)
		end
		return
	end

	local actionKey = actionKind .. ":" .. tostring(actionValue)
	local currentSpell = (actionKind == "action" and ns.ManaCalc and ns.ManaCalc.ResolveSpellID)
			and ns.ManaCalc.ResolveSpellID(actionValue, overlay.spellID)
		or ((actionKind == "spell") and actionValue or overlay.spellID)
	local sameSpell = (overlay.actionKey == actionKey)
		and (overlay.parsed ~= nil)
		and (currentSpell ~= nil and currentSpell == overlay.resolvedSpellID)

	UpdateButton(button, sameSpell)
end

local function RegisterButton(button)
	if not button or overlays[button] then
		return
	end

	-- Ignore les frames qui ne sont pas de vrais boutons d'action
	if not button.CreateFontString then
		return
	end

	-- Conteneur dédié au-dessus des textures/bordures/cooldowns du bouton
	local container = CreateFrame("Frame", nil, button)
	container:SetAllPoints(button)
	container:SetFrameLevel((button:GetFrameLevel() or 1) + 5)

	local db = CastMetricsDB
	overlays[button] = {
		container = container,
		dmgText = CreateOverlayFontString(container, "CENTER", 0, 0, db and db.centerFontSize or 11),
		castsText = CreateOverlayFontString(container, "BOTTOMRIGHT", -3, 3, db and db.castsFontSize or 10),
		actionKey = nil,
		spellID = nil,
		parsed = nil,
	}

	-- Hook sécurisé (hooksecurefunc ne provoque pas de "taint" sur le bouton protégé)
	if button.UpdateAction then
		hooksecurefunc(button, "UpdateAction", function(self)
			UpdateButtonSmart(self)
		end)
	end

	if button.HookScript then
		button:HookScript("OnShow", function(self)
			UpdateButtonSmart(self)
		end)
	end

	local cdFrame = button.cooldown or button.Cooldown
	if cdFrame and not hookedCooldowns[cdFrame] then
		hookedCooldowns[cdFrame] = true
		local function OnCooldownSet()
			if (not button.IsVisible or button:IsVisible()) and ns.RequestCooldownUpdate then
				ns.RequestCooldownUpdate()
			end
		end
		local function OnCooldownEnd()
			if not button.IsVisible or button:IsVisible() then
				ApplyCooldownVisibility(overlays[button])
			end
		end
		if cdFrame.SetCooldown then
			hooksecurefunc(cdFrame, "SetCooldown", OnCooldownSet)
		end
		if cdFrame.SetCooldownFromDurationObject then
			hooksecurefunc(cdFrame, "SetCooldownFromDurationObject", OnCooldownSet)
		end
		if cdFrame.Clear then
			hooksecurefunc(cdFrame, "Clear", OnCooldownEnd)
		end
		if cdFrame.HookScript then
			cdFrame:HookScript("OnHide", OnCooldownEnd)
			if cdFrame.HasScript and cdFrame:HasScript("OnCooldownDone") then
				cdFrame:HookScript("OnCooldownDone", OnCooldownEnd)
			end
		end
	end

	UpdateButton(button, false)
end

function ns.UpdateAllButtons(onlyMana)
	for button in pairs(overlays) do
		UpdateButton(button, onlyMana)
	end
end

function ns.UpdateAllButtonCooldowns()
	for button, overlay in pairs(overlays) do
		if not button.IsVisible or button:IsVisible() then
			ApplyCooldownVisibility(overlay)
		end
	end
end

function ns.RefreshOverlayFonts()
	local db = CastMetricsDB
	if not db then
		return
	end
	for _, overlay in pairs(overlays) do
		ApplyFontSize(overlay.dmgText, db.centerFontSize or 11)
		ApplyFontSize(overlay.castsText, db.castsFontSize or 10)
	end
end

local function HookLibActionButton(libName)
	if not LibStub then
		return
	end

	local lab = LibStub(libName, true)
	if not lab then
		return
	end

	if lab.GetAllButtons then
		for button in pairs(lab:GetAllButtons()) do
			RegisterButton(button)
		end
	end

	if not hookedLibs[lab] then
		hookedLibs[lab] = true
		if lab.RegisterCallback then
			local token = "CastMetrics_" .. libName
			lab.RegisterCallback(token, "OnButtonCreated", function(_, button)
				RegisterButton(button)
			end)
			lab.RegisterCallback(token, "OnButtonUpdate", function(_, button)
				RegisterButton(button)
				UpdateButtonSmart(button)
			end)
		end
	end
end

local blizzardEventsHooked = false

function ns.InitButtonOverlays()
	-- 1. Méthode moderne Blizzard : boutons enregistrés dans ActionBarButtonEventsFrame
	if ActionBarButtonEventsFrame then
		if ActionBarButtonEventsFrame.frames then
			for _, button in pairs(ActionBarButtonEventsFrame.frames) do
				RegisterButton(button)
			end
		end

		if not blizzardEventsHooked and ActionBarButtonEventsFrame.RegisterFrame then
			blizzardEventsHooked = true
			hooksecurefunc(ActionBarButtonEventsFrame, "RegisterFrame", function(_, button)
				RegisterButton(button)
			end)
		end
	end

	-- 2. Fallback par noms globaux (_G) pour les barres Blizzard standards
	for _, prefix in ipairs(BAR_PREFIXES) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then
				RegisterButton(button)
			end
		end
	end

	-- 3. Addons tiers basés sur LibActionButton-1.0 (Bartender4, ElvUI, etc.)
	for _, libName in ipairs(LAB_LIBRARIES) do
		HookLibActionButton(libName)
	end

	-- 4. Fallback explicite pour les boutons Bartender4 (BT4Button1..180)
	for i = 1, 180 do
		local button = _G["BT4Button" .. i]
		if button then
			RegisterButton(button)
		end
	end
end
