local _, ns = ...

local TooltipParser = {}
ns.TooltipParser = TooltipParser

local function GetRules()
	return ns.GetParserLocale and ns.GetParserLocale() or nil
end

local function MatchesAny(text, patterns, plain)
	if not patterns then
		return false
	end
	for _, pat in ipairs(patterns) do
		if text:find(pat, 1, plain) then
			return true
		end
	end
	return false
end

-- Normalise une ligne de tooltip pour faciliter le pattern matching en Lua :
--   1) supprime les balises de couleur/texture/atlas WoW (|cAARRGGBB, |cnNAME:, |r, |T...|t, |A...|a)
--   2) résout les balises de pluriel (|4singulier:pluriel; -> pluriel) et |n -> \n
--   3) remplace les espaces insécables UTF-8 (\194\160 et \226\128\175) par un espace ASCII normal
--   4) fusionne les séparateurs de milliers selon la locale (ex: "1 234" FR, "1,234" EN, "1.234" DE/ES)
local function NormalizeText(text)
	local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]+:", ""):gsub("|r", "")
	clean = clean:gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", "")
	clean = clean:gsub("|4[^:;]+:([^;]+);", "%1")
	clean = clean:gsub("|n", "\n")
	clean = clean:gsub("\194\160", " "):gsub("\226\128\175", " ")

	local rules = GetRules()
	local thousandPattern = (rules and rules.thousandPattern) or "(%d)[ ,](%d%d%d)"

	-- On boucle pour gérer les grands nombres (ex: 1 234 567) sans toucher aux décimales
	while true do
		local nextText, count = clean:gsub(thousandPattern, "%1%2")
		clean = nextText
		if count == 0 then
			break
		end
	end

	return clean
end

TooltipParser.NormalizeText = NormalizeText

-- Détermine si une ligne décrit des dégâts ou des soins réels (et non un buff de stats / changeforme)
local function DetectLineKind(lowerText, rules)
	if not rules then
		return nil
	end

	if MatchesAny(lowerText, rules.ignoreLineWords, true) then
		return nil
	end

	local padded = lowerText .. " "
	if MatchesAny(padded, rules.healDetectPatterns, false) then
		return "heal"
	end
	if MatchesAny(padded, rules.damageDetectPatterns, false) then
		return "damage"
	end

	return nil
end

local function DetectContextKind(lowerText, rules)
	if not rules or MatchesAny(lowerText, rules.ignoreLineWords, true) then
		return nil
	end

	local padded = lowerText .. " "
	if MatchesAny(padded, rules.healContextWords, false) then
		return "heal"
	end
	if MatchesAny(padded, rules.damageContextWords, false) then
		return "damage"
	end

	return nil
end

local function DetectSchool(lowerText, rules)
	if not rules or not rules.schoolPatterns then
		return nil
	end

	for _, entry in ipairs(rules.schoolPatterns) do
		if MatchesAny(lowerText, entry.words, true) then
			return entry.school
		end
	end
	return nil
end

local function MakeResult(minVal, maxVal, kind, details)
	local minNum = tonumber(minVal)
	local maxNum = tonumber(maxVal or minVal)
	if not minNum or not maxNum then
		return nil
	end

	-- Garde-fou si les bornes étaient inversées
	if maxNum < minNum then
		minNum, maxNum = maxNum, minNum
	end

	return {
		min = minNum,
		max = maxNum,
		avg = (minNum + maxNum) / 2,
		kind = kind,
		school = details and details.school or nil,
		directMin = details and details.directMin or minNum,
		directMax = details and details.directMax or maxNum,
		dotMin = details and details.dotMin or 0,
		dotMax = details and details.dotMax or 0,
		duration = details and details.duration or nil,
	}
end

local function ParseDecimal(str)
	if not str then
		return nil
	end
	return tonumber((str:gsub(",", ".")))
end

-- Normalise les unités de durée locales ("4 s", "4 Sek.", "4 seg.") vers "sec"
local function NormalizeDurationUnits(text, rules)
	local out = text .. " "
	if rules and rules.durationUnitPatterns then
		for _, entry in ipairs(rules.durationUnitPatterns) do
			out = out:gsub(entry.pattern, entry.replacement)
		end
	end
	return out
end

-- Si un segment indique "toutes les X sec pendant Y sec", multiplie par le nombre de ticks
local function GetTickMultiplier(lower, endIdx, rules)
	if not rules then
		return 1
	end

	local after = NormalizeDurationUnits(lower:sub(endIdx + 1, endIdx + 64), rules)
	local clause = after:match("^[^%.,]+") or after

	if rules.intervalDurationPatterns then
		for _, pat in ipairs(rules.intervalDurationPatterns) do
			local interval, duration = clause:match(pat)
			if interval and duration then
				local iv = ParseDecimal(interval)
				local dur = ParseDecimal(duration)
				if iv and dur and iv > 0 then
					local ticks = math.floor((dur / iv) + 0.5)
					if ticks >= 1 and ticks <= 60 then
						return ticks
					end
				end
			end
		end
	end

	if rules.perSecDurationPatterns then
		for _, pat in ipairs(rules.perSecDurationPatterns) do
			local perSecDur = clause:match(pat)
			if perSecDur then
				local dur = ParseDecimal(perSecDur)
				if dur and dur >= 1 and dur <= 60 then
					return dur
				end
			end
		end
	end

	return 1
end

-- Détecte si le segment courant est périodique sans déborder sur un effet secondaire (ex: "118 et Déchirure pendant 4 s")
local function GetSegmentDuration(lower, startIdx, endIdx, rules)
	if not rules then
		return nil
	end

	local after = NormalizeDurationUnits(lower:sub(endIdx + 1, endIdx + 64), rules)
	local dur = nil

	if rules.overDurationPatterns then
		for _, pat in ipairs(rules.overDurationPatterns) do
			dur = after:match(pat)
			if dur then
				break
			end
		end
	end

	if not dur and rules.forDurationPatterns then
		for _, pat in ipairs(rules.forDurationPatterns) do
			local beforePrefix, forDur = after:match(pat)
			if forDur and beforePrefix then
				local paddedPrefix = " " .. beforePrefix .. " "
				local hasConjunction = false
				if rules.conjunctionWords then
					for _, word in ipairs(rules.conjunctionWords) do
						if paddedPrefix:find("%s" .. word .. "%s+") then
							hasConjunction = true
							break
						end
					end
				end
				if not hasConjunction then
					dur = forDur
					break
				end
			end
		end
	end

	if not dur and rules.beforeDurationPatterns and startIdx and startIdx > 1 then
		local before = NormalizeDurationUnits(lower:sub(math.max(1, startIdx - 48), startIdx - 1), rules)
		for _, pat in ipairs(rules.beforeDurationPatterns) do
			dur = before:match(pat)
			if dur then
				break
			end
		end
	end

	if dur then
		local num = ParseDecimal(dur)
		if num and num > 0 and num <= 120 then
			return num
		end
	end

	if rules.intervalDurationPatterns then
		for _, pat in ipairs(rules.intervalDurationPatterns) do
			local _, tickDur = after:match("^[^%.,%d]*" .. pat)
			if tickDur then
				local num = ParseDecimal(tickDur)
				if num and num > 0 and num <= 120 then
					return num
				end
			end
		end
	end

	return nil
end

-- Extrait min/max (en cumulant direct + DoT/HoT) depuis une ligne de texte selon la locale active
function TooltipParser.ParseLine(rawText, fallbackKind)
	-- IMPORTANT (WoW Forever / Midnight) : toujours tester ns.IsSecret() AVANT toute comparaison (==, etc.)
	if not rawText or ns.IsSecret(rawText) or rawText == "" then
		return nil
	end

	local rules = GetRules()
	if not rules or not rules.chunkPatterns then
		return nil
	end

	local text = NormalizeText(rawText)
	local lower = text:lower()
	local lineKind = DetectLineKind(lower, rules) or fallbackKind
	if not lineKind then
		return nil
	end
	local lineSchool = DetectSchool(lower, rules)

	local totals = {}
	local primaryKind = nil
	local pos = 1

	while pos <= #lower do
		local bestStart, bestEnd, bestMin, bestMax, bestKind

		for _, spec in ipairs(rules.chunkPatterns) do
			if not spec.requiresLineKind or spec.requiresLineKind == lineKind then
				local s, e, c1, c2 = lower:find(spec.pattern, pos)
				if s and (not bestStart or s < bestStart) then
					bestStart = s
					bestEnd = e
					bestKind = spec.useLineKind and lineKind or spec.kind
					bestMin = ParseDecimal(c1)
					bestMax = ParseDecimal(spec.range and c2 or c1)
				end
			end
		end

		if not bestStart then
			break
		end

		if bestMin and bestMax then
			if bestMax < bestMin then
				bestMin, bestMax = bestMax, bestMin
			end

			local mult = GetTickMultiplier(lower, bestEnd, rules)
			local segMin = bestMin * mult
			local segMax = bestMax * mult
			local segDuration = GetSegmentDuration(lower, bestStart, bestEnd, rules)

			local bucket = totals[bestKind]
			if not bucket then
				bucket = { min = 0, max = 0, directMin = 0, directMax = 0, dotMin = 0, dotMax = 0, duration = nil }
				totals[bestKind] = bucket
			end
			bucket.min = bucket.min + segMin
			bucket.max = bucket.max + segMax

			if segDuration or mult > 1 then
				bucket.dotMin = bucket.dotMin + segMin
				bucket.dotMax = bucket.dotMax + segMax
				bucket.duration = bucket.duration or segDuration
			else
				bucket.directMin = bucket.directMin + segMin
				bucket.directMax = bucket.directMax + segMax
			end

			if not primaryKind then
				primaryKind = bestKind
			end
		end

		pos = bestEnd + 1
	end

	if primaryKind and totals[primaryKind] then
		local t = totals[primaryKind]
		t.school = lineSchool
		return MakeResult(t.min, t.max, primaryKind, t)
	end

	return nil
end

local function GetCurrentComboPoints()
	if Enum and Enum.PowerType and Enum.PowerType.ComboPoints and UnitPower then
		local cp = UnitPower("player", Enum.PowerType.ComboPoints)
		if ns.IsSecret(cp) then
			return nil, true
		end
		if type(cp) == "number" then
			return cp, false
		end
	end

	if GetComboPoints then
		local ok, cp = pcall(GetComboPoints, "player", "target")
		if ok and type(cp) == "number" and not ns.IsSecret(cp) then
			return cp, false
		end
	end

	return nil, false
end

-- Parse une ligne de palier de points de combo (ex: "1 point : 118 et Déchirure pendant 4 s")
local function ParseComboTierLine(rawSubLine, contextKind, contextSchool, rules)
	if not rules then
		return nil, nil
	end

	local text = NormalizeText(rawSubLine)
	local lower = text:lower()
	local cpStr, rest
	if rules.comboLinePatterns then
		for _, pat in ipairs(rules.comboLinePatterns) do
			cpStr, rest = lower:match(pat)
			if cpStr and rest then
				break
			end
		end
	elseif rules.comboLinePattern then
		cpStr, rest = lower:match(rules.comboLinePattern)
	end
	if not cpStr or not rest then
		return nil, nil
	end

	local cp = tonumber(cpStr)
	if not cp or cp < 1 or cp > 10 then
		return nil, nil
	end

	local parsed = TooltipParser.ParseLine(rest, contextKind)
	if parsed then
		if not parsed.school and contextSchool then
			parsed.school = contextSchool
		end
		return cp, parsed
	end

	if not contextKind then
		return nil, nil
	end

	local minVal, maxVal, endIdx
	if rules.comboRangePatterns then
		for _, pat in ipairs(rules.comboRangePatterns) do
			local s1, e1, a, b = rest:find(pat)
			if s1 then
				minVal, maxVal, endIdx = ParseDecimal(a), ParseDecimal(b), e1
				break
			end
		end
	end

	if not minVal then
		local s2, e2, v = rest:find("^(%d+[%.,]?%d*)")
		if s2 then
			minVal = ParseDecimal(v)
			maxVal = minVal
			endIdx = e2
		end
	end

	if not minVal or not maxVal or not endIdx then
		return nil, nil
	end
	if maxVal < minVal then
		minVal, maxVal = maxVal, minVal
	end

	local mult = GetTickMultiplier(rest, endIdx, rules)
	local segMin = minVal * mult
	local segMax = maxVal * mult
	local segDuration = GetSegmentDuration(rest, 1, endIdx, rules)

	local details = {
		school = DetectSchool(rest, rules) or contextSchool,
		directMin = (segDuration or mult > 1) and 0 or segMin,
		directMax = (segDuration or mult > 1) and 0 or segMax,
		dotMin = (segDuration or mult > 1) and segMin or 0,
		dotMax = (segDuration or mult > 1) and segMax or 0,
		duration = segDuration,
	}

	return cp, MakeResult(segMin, segMax, contextKind, details)
end

-- Sélectionne les statistiques correspondant au nombre de points de combo actuels.
-- Si allowZeroFallback vaut false (boutons d'action), retourne nil à 0 point de combo pour ne rien afficher.
function TooltipParser.ResolveComboTier(parsed, allowZeroFallback)
	if not parsed or not parsed.comboTiers then
		return parsed
	end

	local cp = GetCurrentComboPoints()
	if not cp or cp < 1 then
		if not allowZeroFallback then
			return nil
		end
		cp = parsed.comboMinTier or 1
	end

	local targetCP = cp
	if parsed.comboMaxTier and targetCP > parsed.comboMaxTier then
		targetCP = parsed.comboMaxTier
	end

	local chosenTier = parsed.comboTiers[targetCP]
	local usedCP = targetCP
	if not chosenTier then
		for tierCP = targetCP, 1, -1 do
			if parsed.comboTiers[tierCP] then
				chosenTier = parsed.comboTiers[tierCP]
				usedCP = tierCP
				break
			end
		end
	end
	if not chosenTier then
		usedCP = parsed.comboMinTier or 1
		chosenTier = parsed.comboTiers[usedCP]
	end
	if not chosenTier then
		return parsed
	end

	return {
		min = chosenTier.min,
		max = chosenTier.max,
		avg = chosenTier.avg,
		kind = chosenTier.kind,
		school = chosenTier.school,
		directMin = chosenTier.directMin,
		directMax = chosenTier.directMax,
		dotMin = chosenTier.dotMin,
		dotMax = chosenTier.dotMax,
		duration = chosenTier.duration,
		comboTiers = parsed.comboTiers,
		comboMinTier = parsed.comboMinTier,
		comboMaxTier = parsed.comboMaxTier,
		activeComboPoints = usedCP,
	}
end

-- Parcourt un tableau de lignes de tooltip (TooltipData.lines) et retourne (parsedResult, hadSecret)
function TooltipParser.ParseLines(lines)
	if not lines or ns.IsSecret(lines) then
		return nil, true
	end

	local rules = GetRules()
	local comboHint = (rules and rules.comboHintWord) or "combo"

	local hadSecret = false
	local firstParsed = nil
	local contextKind = nil
	local contextSchool = nil
	local sawComboHint = false
	local comboTiers = {}
	local comboCount = 0
	local comboMinTier, comboMaxTier

	-- On commence à l'index 2 pour ignorer le titre du sort (ligne 1)
	for i = 2, #lines do
		local line = lines[i]
		if line and not ns.IsSecret(line) and line.leftText then
			if ns.IsSecret(line.leftText) then
				hadSecret = true
			else
				for subLine in NormalizeText(line.leftText):gmatch("[^\r\n]+") do
					local lowerSub = subLine:lower()
					if lowerSub:find(comboHint, 1, true) then
						sawComboHint = true
					end
					if not contextKind then
						contextKind = DetectContextKind(lowerSub, rules)
					end
					if not contextSchool then
						contextSchool = DetectSchool(lowerSub, rules)
					end

					local cp, tierResult = ParseComboTierLine(subLine, contextKind, contextSchool, rules)
					if cp and tierResult then
						if not comboTiers[cp] then
							comboCount = comboCount + 1
						end
						comboTiers[cp] = tierResult
						if not comboMinTier or cp < comboMinTier then
							comboMinTier = cp
						end
						if not comboMaxTier or cp > comboMaxTier then
							comboMaxTier = cp
						end
					elseif not firstParsed then
						local parsed = TooltipParser.ParseLine(subLine)
						if parsed then
							firstParsed = parsed
						end
					end
				end
			end
		end
	end

	if comboCount >= 2 or (comboCount == 1 and sawComboHint) then
		return TooltipParser.ResolveComboTier({
			comboTiers = comboTiers,
			comboMinTier = comboMinTier,
			comboMaxTier = comboMaxTier,
		}, true), hadSecret
	end

	return firstParsed, hadSecret
end

local function ExtractTooltipValues(tooltipData)
	if not tooltipData then
		return nil, nil, false
	end
	if ns.IsSecret(tooltipData) or not tooltipData.lines or ns.IsSecret(tooltipData.lines) then
		return nil, nil, true
	end

	local spellID = (tooltipData.id and not ns.IsSecret(tooltipData.id)) and tooltipData.id or nil
	local parsed, hadSecret = TooltipParser.ParseLines(tooltipData.lines)
	return parsed, spellID, hadSecret
end

-- Interroge C_TooltipInfo.GetAction(slot) et retourne (parsedResult, tooltipSpellID, hadSecret)
function TooltipParser.GetActionValues(slot)
	if not C_TooltipInfo or not C_TooltipInfo.GetAction then
		return nil, nil, false
	end
	return ExtractTooltipValues(C_TooltipInfo.GetAction(slot))
end

-- Interroge C_TooltipInfo.GetSpellByID(spellID) et retourne (parsedResult, tooltipSpellID, hadSecret)
function TooltipParser.GetSpellValues(spellID)
	if not spellID or not C_TooltipInfo or not C_TooltipInfo.GetSpellByID then
		return nil, nil, false
	end
	return ExtractTooltipValues(C_TooltipInfo.GetSpellByID(spellID))
end
