local _, ns = ...

local ManaCalc = {}
ns.ManaCalc = ManaCalc

-- Résout le spellID associé à un slot de barre d'action
local function ResolveSpellID(slot, tooltipSpellID)
	local actionType, id = GetActionInfo(slot)
	if not ns.IsSecret(actionType) and not ns.IsSecret(id) then
		if actionType == "spell" and type(id) == "number" then
			return id
		elseif actionType == "macro" and type(id) == "number" and GetMacroSpell then
			local macroSpellID = GetMacroSpell(id)
			if macroSpellID and not ns.IsSecret(macroSpellID) then
				return macroSpellID
			end
		end
	end

	if C_ActionBar and C_ActionBar.GetSpell then
		local barSpellID = C_ActionBar.GetSpell(slot)
		if barSpellID and not ns.IsSecret(barSpellID) then
			return barSpellID
		end
	end

	if tooltipSpellID and not ns.IsSecret(tooltipSpellID) then
		return tooltipSpellID
	end

	return nil
end

ManaCalc.ResolveSpellID = ResolveSpellID

-- Ensemble des ressources principales supportées (Mana, Rage, Énergie, Focalisation, etc.)
local PRIMARY_POWER_TYPES = {}
if Enum and Enum.PowerType then
	for _, key in ipairs({
		"Mana",
		"Rage",
		"Focus",
		"Energy",
		"RunicPower",
		"LunarPower",
		"Maelstrom",
		"Insanity",
		"Fury",
		"Pain",
	}) do
		if Enum.PowerType[key] then
			PRIMARY_POWER_TYPES[Enum.PowerType[key]] = true
		end
	end
end

-- Récupère le coût effectif et le type de ressource d'un sort via l'API moderne C_Spell
-- Retourne (cost, powerType, isSecret)
function ManaCalc.GetSpellResourceCost(spellID)
	if not spellID or not C_Spell or not C_Spell.GetSpellPowerCost then
		return nil, nil, false
	end

	local costs = C_Spell.GetSpellPowerCost(spellID)
	if not costs then
		return nil, nil, false
	end
	if ns.IsSecret(costs) then
		return nil, nil, true
	end

	local fallbackCost, fallbackType
	local hadSecret = false
	for _, costInfo in ipairs(costs) do
		if costInfo then
			if ns.IsSecret(costInfo) or ns.IsSecret(costInfo.type) or ns.IsSecret(costInfo.cost) then
				hadSecret = true
			elseif costInfo.cost and costInfo.cost > 0 then
				if PRIMARY_POWER_TYPES[costInfo.type] then
					return costInfo.cost, costInfo.type, hadSecret
				elseif not fallbackCost then
					fallbackCost = costInfo.cost
					fallbackType = costInfo.type
				end
			end
		end
	end

	return fallbackCost, fallbackType, hadSecret
end

-- Caches des courbes C_CurveUtil (indexées par "cost:maxPower") et des maximums de ressource connus
local stepCurveCache = {}
local colorCurveCache = {}
local lastKnownMaxPower = {}

local function GetMaxPower(powerType)
	local rawMax = UnitPowerMax("player", powerType)
	if rawMax and not ns.IsSecret(rawMax) and rawMax > 0 then
		lastKnownMaxPower[powerType] = rawMax
		return rawMax
	end

	if lastKnownMaxPower[powerType] then
		return lastKnownMaxPower[powerType]
	end

	-- Valeurs maximales standard pour Rage / Énergie / Focalisation si UnitPowerMax est secret
	if Enum and Enum.PowerType then
		if
			powerType == Enum.PowerType.Rage
			or powerType == Enum.PowerType.Energy
			or powerType == Enum.PowerType.Focus
			or powerType == Enum.PowerType.RunicPower
		then
			return 100
		end
	end

	return nil
end

function ManaCalc.CacheMaxPowers()
	for powerType in pairs(PRIMARY_POWER_TYPES) do
		local rawMax = UnitPowerMax("player", powerType)
		if rawMax and not ns.IsSecret(rawMax) and rawMax > 0 then
			lastKnownMaxPower[powerType] = rawMax
		end
	end
end

local function GetOrCreateStepCurve(cost, maxPower)
	local key = cost .. ":" .. maxPower
	local curve = stepCurveCache[key]
	if curve then
		return curve
	end

	if not C_CurveUtil or not C_CurveUtil.CreateCurve or not Enum or not Enum.LuaCurveType then
		return nil
	end

	curve = C_CurveUtil.CreateCurve()
	curve:SetType(Enum.LuaCurveType.Step)

	-- UnitPowerPercent évalue dans [0.0, 1.0] et LuaCurveObject accepte au maximum 256 points
	curve:AddPoint(0, 0)
	local maxSteps = math.min(255, math.floor(maxPower / cost))
	for i = 1, maxSteps do
		local threshold = math.max(0.0001, math.min(1, (i * cost) / maxPower - 1e-5))
		curve:AddPoint(threshold, i)
	end

	stepCurveCache[key] = curve
	return curve
end

local function GetOrCreateColorCurve(cost, maxPower)
	local key = cost .. ":" .. maxPower
	local curve = colorCurveCache[key]
	if curve then
		return curve
	end

	if not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not Enum or not Enum.LuaCurveType or not CreateColor then
		return nil
	end

	curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)
	curve:AddPoint(0, CreateColor(1, 0.25, 0.25, 1)) -- 0 cast : rouge

	if cost <= maxPower then
		curve:AddPoint(math.max(0.0001, cost / maxPower - 1e-5), CreateColor(1, 0.5, 0.15, 1)) -- 1 cast : orange
	end
	if (2 * cost) <= maxPower then
		curve:AddPoint(math.max(0.0001, (2 * cost) / maxPower - 1e-5), CreateColor(1, 0.85, 0.2, 1)) -- 2-4 casts : jaune
	end
	if (5 * cost) <= maxPower then
		curve:AddPoint(math.max(0.0001, (5 * cost) / maxPower - 1e-5), CreateColor(0.4, 0.85, 1, 1)) -- 5+ casts : bleu clair
	end

	colorCurveCache[key] = curve
	return curve
end

-- Retourne (nombreDeCastsRestants, coutRessource, powerType, isSecret, secretColor) pour un spellID donné
function ManaCalc.GetRemainingCastsForSpell(spellID)
	local cost, powerType, costSecret = ManaCalc.GetSpellResourceCost(spellID)
	if not cost or cost <= 0 or powerType == nil then
		return nil, nil, nil, costSecret, nil
	end

	-- Met à jour le cache de maxPower dès qu'il est lisible
	local maxPower = GetMaxPower(powerType)

	local currentPower = UnitPower("player", powerType)
	if not currentPower then
		return nil, cost, powerType, false, nil
	end

	-- Si la ressource est "secrète", on passe les courbes à l'API C++ UnitPowerPercent (autorisée même depuis du code addon)
	if ns.IsSecret(currentPower) then
		if maxPower and maxPower > 0 and UnitPowerPercent then
			local stepCurve = GetOrCreateStepCurve(cost, maxPower)
			if stepCurve then
				local ok, secretCasts = pcall(UnitPowerPercent, "player", powerType, false, stepCurve)
				if ok and secretCasts ~= nil then
					local colorCurve = GetOrCreateColorCurve(cost, maxPower)
					local secretColor = nil
					if colorCurve then
						local okColor, evalColor = pcall(UnitPowerPercent, "player", powerType, false, colorCurve)
						if okColor then
							secretColor = evalColor
						end
					end
					return secretCasts, cost, powerType, true, secretColor
				end
			end
		end
		return nil, cost, powerType, true, nil
	end

	return math.floor(currentPower / cost), cost, powerType, false, nil
end

-- Retourne (nombreDeCastsRestants, coutRessource, powerType, isSecret, secretColor) pour un slot donné
function ManaCalc.GetRemainingCasts(slot, tooltipSpellID)
	local spellID = ResolveSpellID(slot, tooltipSpellID)
	return ManaCalc.GetRemainingCastsForSpell(spellID)
end
