local _, ns = ...

-- Table associant chaque bouton d'action à ses FontStrings et à son cache :
-- overlays[button] = { dmgText = FontString, castsText = FontString, slot = number, spellID = number }
local overlays = {}

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

local function CreateOverlayFontString(parentFrame, anchorPoint, xOffset, yOffset, fontSize)
	local fs = parentFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	local fontPath = GameFontNormalSmall and GameFontNormalSmall:GetFont()
	if fontPath then
		fs:SetFont(fontPath, fontSize or 10, "OUTLINE")
	end

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

local function FormatDamageValue(parsed, db)
	if not parsed then
		return ""
	end

	if db.displayMode == "range" and parsed.min ~= parsed.max then
		return ns.FormatNumber(parsed.min) .. "-" .. ns.FormatNumber(parsed.max)
	end

	return ns.FormatNumber(parsed.avg)
end

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

local function UpdateButton(button, onlyMana)
	local overlay = overlays[button]
	if not overlay then
		return
	end

	local slot = button.action
	if not slot or ns.IsSecret(slot) or type(slot) ~= "number" or not HasAction(slot) then
		overlay.dmgText:SetText("")
		overlay.castsText:SetText("")
		overlay.slot = nil
		overlay.spellID = nil
		overlay.parsed = nil
		overlay.lastCasts = nil
		return
	end

	local db = CastsButtonDisplayDB
	if not db then
		return
	end

	-- Si seule la mana/ressource a changé et que le slot est identique, on évite de re-parser le tooltip
	local prevSlot = overlay.slot
	local needTooltip = (not onlyMana) or (prevSlot ~= slot)
	if needTooltip then
		overlay.slot = slot
		local parsed, spellID, hadSecret = ns.TooltipParser.GetActionValues(slot)
		-- En combat, si le tooltip devient "secret", on conserve la dernière valeur connue pour le même slot
		if not hadSecret or prevSlot ~= slot then
			overlay.parsed = parsed
		end
		if spellID then
			overlay.spellID = spellID
		elseif prevSlot ~= slot then
			overlay.spellID = nil
		end
	end

	-- 1. Affichage des dégâts / soins
	if db.showDamage and overlay.parsed then
		overlay.dmgText:SetText(FormatDamageValue(overlay.parsed, db))
		if overlay.parsed.kind == "heal" then
			overlay.dmgText:SetTextColor(0.3, 1, 0.45) -- Vert soin
		else
			overlay.dmgText:SetTextColor(1, 0.82, 0.2) -- Or/orange dégâts
		end
	else
		overlay.dmgText:SetText("")
	end

	-- 2. Affichage du nombre de lancers possibles avec la ressource actuelle
	if db.showCasts then
		local casts, _, _, isSecret, secretColor = ns.ManaCalc.GetRemainingCasts(slot, overlay.spellID)
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
		elseif isSecret and prevSlot == slot and overlay.lastCasts ~= nil then
			overlay.castsText:SetText(tostring(overlay.lastCasts))
			ApplyCastsColor(overlay.castsText, overlay.lastCasts)
		else
			overlay.lastCasts = nil
			overlay.castsText:SetText("")
		end
	else
		overlay.lastCasts = nil
		overlay.castsText:SetText("")
	end
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

	overlays[button] = {
		container = container,
		dmgText = CreateOverlayFontString(container, "CENTER", 0, 0, 11),
		castsText = CreateOverlayFontString(container, "BOTTOMRIGHT", -3, 3, 10),
		slot = nil,
		spellID = nil,
		parsed = nil,
	}

	-- Hook sécurisé (hooksecurefunc ne provoque pas de "taint" sur le bouton protégé)
	if button.UpdateAction then
		hooksecurefunc(button, "UpdateAction", function(self)
			UpdateButton(self, false)
		end)
	end

	UpdateButton(button, false)
end

function ns.UpdateAllButtons(onlyMana)
	for button in pairs(overlays) do
		UpdateButton(button, onlyMana)
	end
end

function ns.InitButtonOverlays()
	-- 1. Méthode moderne : récupérer les boutons enregistrés dans ActionBarButtonEventsFrame
	if ActionBarButtonEventsFrame then
		if ActionBarButtonEventsFrame.frames then
			for _, button in pairs(ActionBarButtonEventsFrame.frames) do
				RegisterButton(button)
			end
		end

		if ActionBarButtonEventsFrame.RegisterFrame then
			hooksecurefunc(ActionBarButtonEventsFrame, "RegisterFrame", function(_, button)
				RegisterButton(button)
			end)
		end
	end

	-- 2. Fallback par noms globaux (_G) pour couvrir toutes les barres standards
	for _, prefix in ipairs(BAR_PREFIXES) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then
				RegisterButton(button)
			end
		end
	end
end
