local _, ns = ...

local optionsCategory = nil
local optionsCategoryID = nil
local previewBox = nil

local function GetVarType(kind)
	if Settings and Settings.VarType and Settings.VarType[kind] then
		return Settings.VarType[kind]
	end
	return kind:lower()
end

-- Scanne les barres d'action (1..180) pour lister les sorts de dégâts/soins disponibles pour l'aperçu
local function CollectPreviewSpells()
	local list = {}
	local seen = {}

	for slot = 1, 180 do
		if HasAction(slot) then
			local parsed, tooltipSpellID = ns.TooltipParser.GetActionValues(slot)
			local spellID = (ns.ManaCalc and ns.ManaCalc.ResolveSpellID)
					and ns.ManaCalc.ResolveSpellID(slot, tooltipSpellID)
				or tooltipSpellID
			if parsed and spellID and not ns.IsSecret(spellID) and not seen[spellID] then
				seen[spellID] = true
				local spellInfo = (C_Spell and C_Spell.GetSpellInfo) and C_Spell.GetSpellInfo(spellID) or nil
				local name = (spellInfo and not ns.IsSecret(spellInfo.name)) and spellInfo.name
					or ("Sort #" .. tostring(spellID))
				local subtext = (C_Spell and C_Spell.GetSpellSubtext) and C_Spell.GetSpellSubtext(spellID) or nil
				if subtext and not ns.IsSecret(subtext) and subtext ~= "" then
					name = name .. " (" .. subtext .. ")"
				end
				table.insert(list, { spellID = spellID, name = name })
			end
		end
	end

	table.sort(list, function(a, b)
		return a.name < b.name
	end)

	return list
end

local function ResolvePreviewSpellID()
	local db = CastsButtonDisplayDB
	local chosen = db and db.previewSpellID or 0
	if chosen and chosen > 0 then
		return chosen
	end

	local spells = CollectPreviewSpells()
	if spells[1] then
		return spells[1].spellID
	end

	return nil
end

local function CreatePreviewBox(parent)
	local box = CreateFrame("Frame", nil, parent)
	box:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 20, 16)
	box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 16)
	box:SetHeight(88)
	box:Hide()

	-- Fond sobre et bordure fine (1px) sans dépendance à BackdropTemplate
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(box)
	bg:SetColorTexture(0.06, 0.07, 0.1, 0.85)

	local function AddBorderEdge(point1, point2, width, height)
		local edge = box:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(0.28, 0.55, 0.75, 0.65)
		edge:SetPoint(point1, box, point1, 0, 0)
		edge:SetPoint(point2, box, point2, 0, 0)
		if width then
			edge:SetWidth(width)
		end
		if height then
			edge:SetHeight(height)
		end
	end
	AddBorderEdge("TOPLEFT", "TOPRIGHT", nil, 1)
	AddBorderEdge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
	AddBorderEdge("TOPLEFT", "BOTTOMLEFT", 1, nil)
	AddBorderEdge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

	local header = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
	header:SetText("|cff00ccffAperçu du bouton (en direct)|r")

	local btn = CreateFrame("Button", nil, box)
	btn:SetSize(44, 44)
	btn:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 14, 12)

	local btnBorder = btn:CreateTexture(nil, "BACKGROUND")
	btnBorder:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
	btnBorder:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
	btnBorder:SetColorTexture(0.35, 0.35, 0.4, 0.9)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(btn)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local overlayContainer = CreateFrame("Frame", nil, btn)
	overlayContainer:SetAllPoints(btn)
	overlayContainer:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)

	local dmgText = ns.CreateOverlayFontString(overlayContainer, "CENTER", 0, 0, 11)
	local castsText = ns.CreateOverlayFontString(overlayContainer, "BOTTOMRIGHT", -3, 3, 10)

	btn:SetScript("OnEnter", function(self)
		if self.spellID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetSpellByID(self.spellID)
			GameTooltip:Show()
		end
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local spellLabel = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	spellLabel:SetPoint("TOPLEFT", btn, "TOPRIGHT", 12, -2)
	spellLabel:SetPoint("RIGHT", box, "RIGHT", -12, 0)
	spellLabel:SetJustifyH("LEFT")

	local hintLabel = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hintLabel:SetPoint("TOPLEFT", spellLabel, "BOTTOMLEFT", 0, -4)
	hintLabel:SetPoint("RIGHT", box, "RIGHT", -12, 0)
	hintLabel:SetJustifyH("LEFT")
	hintLabel:SetText("Survolez le bouton d'exemple pour inspecter aussi son tooltip enrichi.")

	box.previewBtn = btn
	box.icon = icon
	box.spellLabel = spellLabel
	box.hintLabel = hintLabel
	box.overlay = {
		dmgText = dmgText,
		castsText = castsText,
		lastCasts = nil,
	}

	return box
end

function ns.RefreshOptionsPreview()
	if not previewBox or not previewBox:IsShown() then
		return
	end

	local db = CastsButtonDisplayDB
	if not db then
		return
	end

	ns.ApplyFontSize(previewBox.overlay.dmgText, db.centerFontSize or 11)
	ns.ApplyFontSize(previewBox.overlay.castsText, db.castsFontSize or 10)

	local spellID = ResolvePreviewSpellID()
	if not spellID then
		previewBox.previewBtn.spellID = nil
		previewBox.icon:SetTexture(134400) -- icône "?" standard
		previewBox.overlay.dmgText:SetText("")
		previewBox.overlay.castsText:SetText("")
		previewBox.spellLabel:SetText("Aucun sort de dégâts/soins trouvé sur vos barres")
		return
	end

	previewBox.previewBtn.spellID = spellID

	local spellInfo = (C_Spell and C_Spell.GetSpellInfo) and C_Spell.GetSpellInfo(spellID) or nil
	local iconID = (spellInfo and not ns.IsSecret(spellInfo.iconID)) and spellInfo.iconID or nil
	if not iconID and C_Spell and C_Spell.GetSpellTexture then
		iconID = C_Spell.GetSpellTexture(spellID)
	end
	previewBox.icon:SetTexture((iconID and not ns.IsSecret(iconID)) and iconID or 134400)

	local name = (spellInfo and not ns.IsSecret(spellInfo.name)) and spellInfo.name or ("Sort #" .. tostring(spellID))
	local subtext = (C_Spell and C_Spell.GetSpellSubtext) and C_Spell.GetSpellSubtext(spellID) or nil
	if subtext and not ns.IsSecret(subtext) and subtext ~= "" then
		name = name .. " (" .. subtext .. ")"
	end
	previewBox.spellLabel:SetText(name)

	-- Lecture du tooltip du sort pour alimenter l'aperçu
	local parsed = nil
	if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
		local tooltipData = C_TooltipInfo.GetSpellByID(spellID)
		if tooltipData and not ns.IsSecret(tooltipData) and tooltipData.lines then
			parsed = ns.TooltipParser.ParseLines(tooltipData.lines)
		end
	end

	if db.showDamage and parsed and ns.FormatCenterStat then
		local text, r, g, b = ns.FormatCenterStat(parsed, spellID, db)
		previewBox.overlay.dmgText:SetText(text)
		previewBox.overlay.dmgText:SetTextColor(r, g, b)
	else
		previewBox.overlay.dmgText:SetText("")
	end

	if db.showCasts and ns.ManaCalc and ns.ManaCalc.GetRemainingCastsForSpell and ns.RenderCastsText then
		local casts, _, _, isSecret, secretColor = ns.ManaCalc.GetRemainingCastsForSpell(spellID)
		ns.RenderCastsText(previewBox.overlay, casts, isSecret, secretColor, false)
	else
		previewBox.overlay.castsText:SetText("")
	end
end

local function SyncPreviewVisibility()
	if not previewBox or not SettingsPanel then
		return
	end

	local current = SettingsPanel.GetCurrentCategory and SettingsPanel:GetCurrentCategory()
	if SettingsPanel:IsShown() and current == optionsCategory then
		previewBox:Show()
		ns.RefreshOptionsPreview()
	else
		previewBox:Hide()
	end
end

local function RegisterCheckbox(category, varKey, label, tooltip, defaultValue, onChanged)
	local setting = Settings.RegisterProxySetting(
		category,
		"CBD_" .. varKey,
		GetVarType("Boolean"),
		label,
		defaultValue,
		function()
			return CastsButtonDisplayDB and CastsButtonDisplayDB[varKey]
		end,
		function(value)
			if CastsButtonDisplayDB then
				CastsButtonDisplayDB[varKey] = value
			end
			if onChanged then
				onChanged(value)
			end
			ns.RefreshOptionsPreview()
		end
	)
	Settings.CreateCheckbox(category, setting, tooltip)
end

local function RegisterSlider(category, varKey, label, tooltip, defaultValue, minVal, maxVal, step, onChanged)
	local setting = Settings.RegisterProxySetting(
		category,
		"CBD_" .. varKey,
		GetVarType("Number"),
		label,
		defaultValue,
		function()
			return (CastsButtonDisplayDB and CastsButtonDisplayDB[varKey]) or defaultValue
		end,
		function(value)
			if CastsButtonDisplayDB then
				CastsButtonDisplayDB[varKey] = value
			end
			if onChanged then
				onChanged(value)
			end
			ns.RefreshOptionsPreview()
		end
	)

	local sliderOptions = Settings.CreateSliderOptions(minVal, maxVal, step)
	if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return string.format("%d", value)
		end)
	end

	Settings.CreateSlider(category, setting, sliderOptions, tooltip)
end

local function GetCenterStatOptions()
	local container = Settings.CreateControlTextContainer()
	container:Add("avg", "Moyenne de base (Direct + DoT/HoT)")
	container:Add("weighted", "Moyenne pondérée (avec % critique)")
	container:Add("range", "Intervalle (Min-Max)")
	container:Add("crit", "Coup critique estimé")
	container:Add("dpm", "Efficacité (DPM / HPM / DPR)")
	container:Add("dps", "DPS / HPS (par temps de cast)")
	return container:GetData()
end

local function GetPreviewSpellOptions()
	local container = Settings.CreateControlTextContainer()
	container:Add(0, "Automatique (1er sort des barres)")

	local spells = CollectPreviewSpells()
	local currentID = CastsButtonDisplayDB and CastsButtonDisplayDB.previewSpellID or 0
	local foundCurrent = (currentID == 0)

	for _, entry in ipairs(spells) do
		container:Add(entry.spellID, entry.name)
		if entry.spellID == currentID then
			foundCurrent = true
		end
	end

	-- Si un spellID sauvegardé n'est plus sur les barres, on le garde sélectionnable
	if currentID and currentID > 0 and not foundCurrent then
		local info = (C_Spell and C_Spell.GetSpellInfo) and C_Spell.GetSpellInfo(currentID) or nil
		local fallbackName = (info and not ns.IsSecret(info.name)) and info.name or ("Sort #" .. tostring(currentID))
		container:Add(currentID, fallbackName)
	end

	return container:GetData()
end

function ns.InitOptions()
	if not Settings or not Settings.RegisterVerticalLayoutCategory or not Settings.RegisterAddOnCategory then
		return
	end

	local category = Settings.RegisterVerticalLayoutCategory("CastsButtonDisplay")
	optionsCategory = category

	-- 1. Statistique centrale sur le bouton
	RegisterCheckbox(
		category,
		"showDamage",
		"Afficher la stat centrale",
		"Affiche ou masque la valeur affichée au centre des boutons d'action.",
		true,
		function()
			ns.RequestUpdate(false)
		end
	)

	local centerStatSetting = Settings.RegisterProxySetting(
		category,
		"CBD_centerStat",
		GetVarType("String"),
		"Statistique centrale",
		"avg",
		function()
			return (CastsButtonDisplayDB and CastsButtonDisplayDB.centerStat) or "avg"
		end,
		function(value)
			if CastsButtonDisplayDB then
				CastsButtonDisplayDB.centerStat = value
			end
			ns.RequestUpdate(false)
			ns.RefreshOptionsPreview()
		end
	)
	Settings.CreateDropdown(
		category,
		centerStatSetting,
		GetCenterStatOptions,
		"Choisissez la statistique affichée au milieu de chaque bouton d'action."
	)

	RegisterSlider(
		category,
		"centerFontSize",
		"Taille du texte central",
		"Ajuste la taille de la police au centre du bouton (pratique pour lire un gros DPM ou DPS).",
		11,
		8,
		18,
		1,
		function()
			if ns.RefreshOverlayFonts then
				ns.RefreshOverlayFonts()
			end
		end
	)

	-- 2. Compteur de lancers en bas à droite
	RegisterCheckbox(
		category,
		"showCasts",
		"Afficher les lancers possibles",
		"Affiche en bas à droite combien de fois vous pouvez lancer le sort avec votre ressource actuelle.",
		true,
		function()
			ns.RequestUpdate(true)
		end
	)

	RegisterSlider(
		category,
		"castsFontSize",
		"Taille du compteur de lancers",
		"Ajuste la taille de la police du compteur en bas à droite du bouton.",
		10,
		8,
		16,
		1,
		function()
			if ns.RefreshOverlayFonts then
				ns.RefreshOverlayFonts()
			end
		end
	)

	-- 3. Formatage et Tooltip
	RegisterCheckbox(
		category,
		"compactNumbers",
		"Format court des grands nombres (1.4k)",
		"Abrège les nombres >= 1000 sur les boutons (ex: 1450 -> 1.4k).",
		true,
		function()
			ns.RequestUpdate(false)
		end
	)

	RegisterCheckbox(
		category,
		"showTooltipStats",
		"Afficher les stats détaillées dans le tooltip",
		"Ajoute la moyenne, le critique pondéré, le DPM/HPM et le DPS/HPS dans les info-bulles des sorts.",
		true
	)

	-- 4. Sélection du sort affiché dans le bouton d'exemple
	local previewSpellSetting = Settings.RegisterProxySetting(
		category,
		"CBD_previewSpellID",
		GetVarType("Number"),
		"Sort d'aperçu",
		0,
		function()
			return (CastsButtonDisplayDB and CastsButtonDisplayDB.previewSpellID) or 0
		end,
		function(value)
			if CastsButtonDisplayDB then
				CastsButtonDisplayDB.previewSpellID = value
			end
			ns.RefreshOptionsPreview()
		end
	)
	Settings.CreateDropdown(
		category,
		previewSpellSetting,
		GetPreviewSpellOptions,
		"Choisissez un de vos sorts pour prévisualiser vos réglages sur le bouton d'exemple ci-dessous."
	)

	Settings.RegisterAddOnCategory(category)
	optionsCategoryID = category:GetID()

	-- Création et synchronisation du panneau d'aperçu sous la liste des options
	if SettingsPanel and SettingsPanel.Container then
		previewBox = CreatePreviewBox(SettingsPanel.Container)

		if SettingsPanel.HookScript then
			SettingsPanel:HookScript("OnShow", SyncPreviewVisibility)
			SettingsPanel:HookScript("OnHide", function()
				if previewBox then
					previewBox:Hide()
				end
			end)
		end
		if SettingsPanel.DisplayCategory then
			hooksecurefunc(SettingsPanel, "DisplayCategory", SyncPreviewVisibility)
		end
		if SettingsPanel.SelectCategory then
			hooksecurefunc(SettingsPanel, "SelectCategory", SyncPreviewVisibility)
		end
		if EventRegistry and EventRegistry.RegisterCallback then
			EventRegistry:RegisterCallback("Settings.CategoryChanged", SyncPreviewVisibility)
		end
	end
end

function ns.OpenOptions()
	if InCombatLockdown and InCombatLockdown() then
		print("|cff00ccff[CastsButtonDisplay]|r Impossible d'ouvrir les options en combat.")
		return
	end
	if Settings and Settings.OpenToCategory and optionsCategoryID then
		Settings.OpenToCategory(optionsCategoryID)
	end
end
