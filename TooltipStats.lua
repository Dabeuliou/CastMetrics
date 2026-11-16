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

local HEADER_TEXT = "|cff00ccffCastsButtonDisplay|r"

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

	local critMult = isPhysical and 2.0 or 1.5
	local critPct = nil

	if isPhysical then
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

local function AppendSpellStats(tooltip, data)
	local db = CastsButtonDisplayDB
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

	local isHeal = (parsed.kind == "heal")
	local kindWord = isHeal and "Soins" or "Dégâts"
	local lr, lg, lb = 0.85, 0.85, 0.85
	local vr, vg, vb = isHeal and 0.35 or 1, isHeal and 1 or 0.82, isHeal and 0.5 or 0.2

	local directAvg = (parsed.directMin + parsed.directMax) / 2
	local dotAvg = (parsed.dotMin + parsed.dotMax) / 2
	local cost, powerType = ns.ManaCalc.GetSpellResourceCost(spellID)
	local critPct, critMult = GetPlayerCritInfo(parsed.school, isHeal, powerType)

	local effectiveAvg = parsed.avg
	if critPct and directAvg > 0 then
		local weightedDirect = directAvg * (1 + (critPct / 100) * (critMult - 1))
		effectiveAvg = weightedDirect + dotAvg
	end

	tooltip:AddLine(" ")
	tooltip:AddLine(HEADER_TEXT)

	-- 1. Moyenne totale + décomposition Direct / Périodique si applicable
	if directAvg > 0 and dotAvg > 0 then
		tooltip:AddDoubleLine(kindWord .. " totaux (moy.)", string.format("%.1f", parsed.avg), lr, lg, lb, vr, vg, vb)
		local durText = parsed.duration and string.format(" (%ds)", parsed.duration) or ""
		tooltip:AddDoubleLine(
			"  Direct / Périodique",
			string.format("%.1f + %.1f%s", directAvg, dotAvg, durText),
			0.65, 0.65, 0.65, 0.9, 0.9, 0.9
		)
	elseif dotAvg > 0 and parsed.duration then
		tooltip:AddDoubleLine(
			string.format("%s totaux (%ds)", kindWord, parsed.duration),
			string.format("%.1f", parsed.avg),
			lr, lg, lb, vr, vg, vb
		)
	else
		tooltip:AddDoubleLine(kindWord .. " moyens", string.format("%.1f", parsed.avg), lr, lg, lb, vr, vg, vb)
	end

	-- 2. Coup critique et moyenne pondérée avec le % de critique réel
	if directAvg > 0 then
		local critDirect = directAvg * critMult
		local critTag = critPct and string.format("×%.1f | %.1f%%", critMult, critPct) or string.format("×%.1f", critMult)
		if dotAvg > 0 then
			tooltip:AddDoubleLine(
				string.format("Critique (%s)", critTag),
				string.format("%.1f (total %.1f)", critDirect, critDirect + dotAvg),
				lr, lg, lb, 1, 0.95, 0.55
			)
		else
			tooltip:AddDoubleLine(string.format("Critique (%s)", critTag), string.format("%.1f", critDirect), lr, lg, lb, 1, 0.95, 0.55)
		end

		if critPct then
			tooltip:AddDoubleLine("Moyenne pondérée (crit)", string.format("%.1f", effectiveAvg), lr, lg, lb, vr, vg, vb)
		end
	end

	-- 3. Efficacité par ressource (DPM / HPM / DPR / DPE) et DPS / HPS (pondérés si crit connu)
	if cost and cost > 0 and powerType ~= nil then
		local effCode, resName = GetEfficiencyLabels(isHeal, powerType)
		tooltip:AddDoubleLine(
			string.format("%s (%s / %s)", effCode, kindWord, resName),
			string.format("%.2f", effectiveAvg / cost),
			lr, lg, lb, 0.4, 0.85, 1
		)
	end

	local spellInfo = (spellID and C_Spell and C_Spell.GetSpellInfo) and C_Spell.GetSpellInfo(spellID) or nil
	local castMs = (spellInfo and not ns.IsSecret(spellInfo.castTime)) and spellInfo.castTime or 0
	local castSec = (castMs or 0) / 1000
	local isEnergy = (Enum and Enum.PowerType and powerType == Enum.PowerType.Energy)
	local gcd = isEnergy and 1.0 or 1.5
	local effectiveSec = math.max(castSec, gcd)
	local perSecCode = isHeal and "HPS" or "DPS"
	local castTag = (castSec > gcd) and string.format("%.1fs cast", castSec) or string.format("%.1fs GCD", gcd)

	tooltip:AddDoubleLine(
		string.format("%s (%s)", perSecCode, castTag),
		string.format("%.1f / s", effectiveAvg / effectiveSec),
		lr, lg, lb, 1, 0.65, 0.25
	)

	if dotAvg > 0 and parsed.duration and parsed.duration > 0 then
		tooltip:AddDoubleLine(
			string.format("%s périodique (%ds)", perSecCode, parsed.duration),
			string.format("%.1f / s", dotAvg / parsed.duration),
			lr, lg, lb, 0.85, 0.7, 0.4
		)
	end

	-- 4. Lancers restants (uniquement si UnitPower est lisible directement)
	if cost and cost > 0 and powerType ~= nil then
		local currentPower = UnitPower("player", powerType)
		if currentPower and not ns.IsSecret(currentPower) then
			local casts = math.floor(currentPower / cost)
			tooltip:AddDoubleLine(
				"Lancers possibles",
				string.format("%d (%d / %d)", casts, currentPower, cost),
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
