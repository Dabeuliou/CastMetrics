local _, ns = ...

local TooltipStats = {}
ns.TooltipStats = TooltipStats

local function GetEfficiencyLabels(isHeal, powerType)
	local prefix = isHeal and "H" or "D"
	if Enum and Enum.PowerType then
		if powerType == Enum.PowerType.Mana then
			return prefix .. "PM", "Mana"
		elseif powerType == Enum.PowerType.Rage then
			return prefix .. "PR", "Rage"
		elseif powerType == Enum.PowerType.Energy then
			return prefix .. "PE", "Énergie"
		elseif powerType == Enum.PowerType.Focus then
			return prefix .. "PF", "Focalisation"
		end
	end
	return prefix .. "PR", "Ress."
end

local HEADER_TEXT = "|cff00ccffCastMetrics|r"

local function HasStatsHeader(tooltip)
	local name = tooltip:GetName()
	local numLines = tooltip:NumLines()
	if not name or not numLines then
		return false
	end

	local startIdx = math.max(1, numLines - 10)
	for i = startIdx, numLines do
		local lineFS = _G[name .. "TextLeft" .. i]
		if lineFS and lineFS.GetText then
			local text = lineFS:GetText()
			if text and not ns.IsSecret(text) and text == HEADER_TEXT then
				return true
			end
		end
	end
	return false
end

local function ResolveTooltipSpellID(data)
	local rawID = (data.id and not ns.IsSecret(data.id)) and data.id or nil
	if not rawID then
		return nil
	end

	if Enum and Enum.TooltipDataType and data.type == Enum.TooltipDataType.Macro and GetMacroSpell then
		local macroSpellID = GetMacroSpell(rawID)
		if macroSpellID and not ns.IsSecret(macroSpellID) then
			return macroSpellID
		end
		return nil
	end

	return rawID
end

local function TryReadCrit(fn, arg)
	if not fn then
		return nil
	end
	local ok, val
	if arg ~= nil then
		ok, val = pcall(fn, arg)
	else
		ok, val = pcall(fn)
	end
	if ok and type(val) == "number" and not ns.IsSecret(val) and val >= 0 and val <= 100 then
		return val
	end
	return nil
end

local function GetPlayerCritInfo(school, isHeal, powerType)
	local isPhysical = (school == 1)
	if not isPhysical and not isHeal and not school and Enum and Enum.PowerType then
		isPhysical = (
			powerType == Enum.PowerType.Rage
			or powerType == Enum.PowerType.Energy
			or powerType == Enum.PowerType.Focus
		)
	end

	-- Sur Retail, tous les sorts et soins ont un multiplicateur critique de base de 2.0 (1.5 en Classic/Forever)
	local critMult = (ns.IS_RETAIL or isPhysical) and 2.0 or 1.5
	local critPct = nil

	if isPhysical or ns.IS_RETAIL then
		if Enum and Enum.PowerType and powerType == Enum.PowerType.Focus and GetRangedCritChance then
			critPct = TryReadCrit(GetRangedCritChance)
		end
		if not critPct then
			critPct = TryReadCrit(GetCritChance)
		end
	else
		if GetSpellCritChance then
			if school and school >= 2 and school <= 7 then
				critPct = TryReadCrit(GetSpellCritChance, school)
			end
			if not critPct then
				critPct = TryReadCrit(GetSpellCritChance, 2) or TryReadCrit(GetSpellCritChance)
			end
		end
		if not critPct then
			critPct = TryReadCrit(GetCritChance)
		end
	end

	return critPct, critMult
end

local function GetEffectiveGCD(isEnergy)
	local baseGcd = isEnergy and 1.0 or 1.5
	if ns.IS_RETAIL and not isEnergy and GetHaste then
		local ok, haste = pcall(GetHaste)
		if ok and type(haste) == "number" and not ns.IsSecret(haste) and haste > 0 then
			return math.max(0.75, baseGcd / (1 + haste / 100))
		end
	end
	return baseGcd
end

-- Calcule toutes les métriques dérivées (moyenne pondérée crit, DPM/HPM, DPS/HPS) pour un sort parsé.
-- Partagé entre le tooltip (TooltipStats) et les boutons d'action (ButtonOverlay).
function TooltipStats.ComputeMetrics(parsed, spellID)
	if not parsed then
		return nil
	end

	local isHeal = (parsed.kind == "heal")
	local kindWord = isHeal and "Soins" or "Dégâts"
	local directAvg = (parsed.directMin + parsed.directMax) / 2
	local dotAvg = (parsed.dotMin + parsed.dotMax) / 2
	local cost, powerType = ns.ManaCalc.GetSpellResourceCost(spellID)
	local critPct, critMult = GetPlayerCritInfo(parsed.school, isHeal, powerType)

	local weightedAvg = parsed.avg
	if critPct then
		if ns.IS_RETAIL then
			-- Sur Retail, les DoT / HoT peuvent aussi faire des coups critiques
			weightedAvg = parsed.avg * (1 + (critPct / 100) * (critMult - 1))
		elseif directAvg > 0 then
			local weightedDirect = directAvg * (1 + (critPct / 100) * (critMult - 1))
			weightedAvg = weightedDirect + dotAvg
		end
	end

	local critDirect = (directAvg > 0) and (directAvg * critMult) or nil
	local critTotal
	if ns.IS_RETAIL then
		local critDot = (dotAvg > 0) and (dotAvg * critMult) or 0
		if critDirect or critDot > 0 then
			critTotal = (critDirect or 0) + critDot
		end
	else
		critTotal = critDirect and (critDirect + dotAvg) or nil
	end

	local dpm, effCode, resName
	if cost and cost > 0 and powerType ~= nil then
		dpm = weightedAvg / cost
		effCode, resName = GetEfficiencyLabels(isHeal, powerType)
	end

	local spellInfo = (spellID and C_Spell and C_Spell.GetSpellInfo) and C_Spell.GetSpellInfo(spellID) or nil
	local castMs = (spellInfo and not ns.IsSecret(spellInfo.castTime)) and spellInfo.castTime or 0
	local castSec = (castMs or 0) / 1000
	local isEnergy = (Enum and Enum.PowerType and powerType == Enum.PowerType.Energy)
	local gcd = GetEffectiveGCD(isEnergy)
	local effectiveSec = math.max(castSec, gcd)
	local perSecCode = isHeal and "HPS" or "DPS"
	local castTag = (castSec > gcd) and string.format("%.1fs cast", castSec) or string.format("%.2gs GCD", gcd)
	local dps = weightedAvg / effectiveSec
	local dotDps = (dotAvg > 0 and parsed.duration and parsed.duration > 0) and (dotAvg / parsed.duration) or nil

	return {
		isHeal = isHeal,
		kindWord = kindWord,
		avg = parsed.avg,
		directAvg = directAvg,
		dotAvg = dotAvg,
		critPct = critPct,
		critMult = critMult,
		critDirect = critDirect,
		critTotal = critTotal,
		weightedAvg = weightedAvg,
		cost = cost,
		powerType = powerType,
		dpm = dpm,
		effCode = effCode,
		resName = resName,
		dps = dps,
		perSecCode = perSecCode,
		castTag = castTag,
		dotDps = dotDps,
	}
end

local function AppendSpellStats(tooltip, data)
	local db = CastMetricsDB
	if not db or not db.showTooltipStats then
		return
	end

	if tooltip ~= GameTooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then
		return
	end

	if HasStatsHeader(tooltip) then
		return
	end

	if not data or ns.IsSecret(data) or not data.lines or ns.IsSecret(data.lines) then
		return
	end

	local spellID = ResolveTooltipSpellID(data)
	local parsed = ns.TooltipParser.ParseLines(data.lines)
	if not parsed then
		return
	end

	local m = TooltipStats.ComputeMetrics(parsed, spellID)
	if not m then
		return
	end

	local lr, lg, lb = 0.85, 0.85, 0.85
	local vr, vg, vb = m.isHeal and 0.35 or 1, m.isHeal and 1 or 0.82, m.isHeal and 0.5 or 0.2

	tooltip:AddLine(" ")
	tooltip:AddLine(HEADER_TEXT)

	-- 1. Moyenne totale + décomposition Direct / Périodique si applicable
	local cpTag = parsed.activeComboPoints
			and string.format(" (%d pt%s)", parsed.activeComboPoints, parsed.activeComboPoints > 1 and "s" or "")
		or ""
	if m.directAvg > 0 and m.dotAvg > 0 then
		tooltip:AddDoubleLine(m.kindWord .. " totaux (moy.)" .. cpTag, string.format("%.1f", m.avg), lr, lg, lb, vr, vg, vb)
		local durText = parsed.duration and string.format(" (%gs)", parsed.duration) or ""
		tooltip:AddDoubleLine(
			"  Direct / Périodique",
			string.format("%.1f + %.1f%s", m.directAvg, m.dotAvg, durText),
			0.65, 0.65, 0.65, 0.9, 0.9, 0.9
		)
	elseif m.dotAvg > 0 and parsed.duration then
		tooltip:AddDoubleLine(
			string.format("%s totaux (%gs)%s", m.kindWord, parsed.duration, cpTag),
			string.format("%.1f", m.avg),
			lr, lg, lb, vr, vg, vb
		)
	else
		tooltip:AddDoubleLine(m.kindWord .. " moyens" .. cpTag, string.format("%.1f", m.avg), lr, lg, lb, vr, vg, vb)
	end

	-- 2. Coup critique et moyenne pondérée avec le % de critique réel
	if m.critDirect or m.critTotal then
		local critTag = m.critPct and string.format("×%.1f | %.1f%%", m.critMult, m.critPct) or string.format("×%.1f", m.critMult)
		if m.critDirect and m.dotAvg > 0 then
			tooltip:AddDoubleLine(
				string.format("Critique (%s)", critTag),
				string.format("%.1f (total %.1f)", m.critDirect, m.critTotal or m.critDirect),
				lr, lg, lb, 1, 0.95, 0.55
			)
		elseif m.critDirect then
			tooltip:AddDoubleLine(string.format("Critique (%s)", critTag), string.format("%.1f", m.critDirect), lr, lg, lb, 1, 0.95, 0.55)
		elseif m.critTotal then
			tooltip:AddDoubleLine(string.format("Critique max (%s)", critTag), string.format("%.1f", m.critTotal), lr, lg, lb, 1, 0.95, 0.55)
		end

		if m.critPct then
			tooltip:AddDoubleLine("Moyenne pondérée (crit)", string.format("%.1f", m.weightedAvg), lr, lg, lb, vr, vg, vb)
		end
	end

	-- 3. Efficacité par ressource (DPM / HPM / DPR / DPE) et DPS / HPS (pondérés si crit connu)
	if m.dpm then
		tooltip:AddDoubleLine(
			string.format("%s (%s / %s)", m.effCode, m.kindWord, m.resName),
			string.format("%.2f", m.dpm),
			lr, lg, lb, 0.4, 0.85, 1
		)
	end

	tooltip:AddDoubleLine(
		string.format("%s (%s)", m.perSecCode, m.castTag),
		string.format("%.1f / s", m.dps),
		lr, lg, lb, 1, 0.65, 0.25
	)

	if m.dotDps and parsed.duration then
		tooltip:AddDoubleLine(
			string.format("%s périodique (%gs)", m.perSecCode, parsed.duration),
			string.format("%.1f / s", m.dotDps),
			lr, lg, lb, 0.85, 0.7, 0.4
		)
	end

	-- 4. Lancers restants (uniquement si UnitPower est lisible directement)
	if m.cost and m.cost > 0 and m.powerType ~= nil then
		local currentPower = UnitPower("player", m.powerType)
		if currentPower and not ns.IsSecret(currentPower) then
			local casts = math.floor(currentPower / m.cost)
			tooltip:AddDoubleLine(
				"Lancers possibles",
				string.format("%d (%d / %d)", casts, currentPower, m.cost),
				lr, lg, lb, 0.4, 0.85, 1
			)
		end
	end

	tooltip:Show()
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	if Enum.TooltipDataType.Spell then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, AppendSpellStats)
	end
	if Enum.TooltipDataType.Macro then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, AppendSpellStats)
	end
end
