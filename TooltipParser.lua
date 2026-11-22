local _, ns = ...

local TooltipParser = {}
ns.TooltipParser = TooltipParser

local lastKnownMaxHealth = nil
local lastKnownWeaponDamage = {
	main = nil,
	offhand = nil,
	ranged = nil,
}

local function GetPlayerMaxHealth()
	if UnitHealthMax then
		local rawMax = UnitHealthMax("player")
		if rawMax and not ns.IsSecret(rawMax) and rawMax > 0 then
			lastKnownMaxHealth = rawMax
			return rawMax
		end
	end
	return lastKnownMaxHealth
end

function TooltipParser.CacheMaxHealth()
	GetPlayerMaxHealth()
end

local function GetPlayerWeaponDamage(weaponSlot)
	local slot = weaponSlot or "main"

	if slot == "ranged" then
		if UnitRangedDamage then
			local ok, _, lowDmg, hiDmg = pcall(UnitRangedDamage, "player")
			if ok and lowDmg and hiDmg and not ns.IsSecret(lowDmg) and not ns.IsSecret(hiDmg) and hiDmg > 0 then
				lastKnownWeaponDamage.ranged = { lowDmg, hiDmg }
				return lowDmg, hiDmg
			end
		end
		local cached = lastKnownWeaponDamage.ranged
		if cached then
			return cached[1], cached[2]
		end
		return nil, nil
	end

	if UnitDamage then
		local ok, lowDmg, hiDmg, offLowDmg, offHiDmg = pcall(UnitDamage, "player")
		if ok then
			if lowDmg and hiDmg and not ns.IsSecret(lowDmg) and not ns.IsSecret(hiDmg) and hiDmg > 0 then
				lastKnownWeaponDamage.main = { lowDmg, hiDmg }
			end
			if offLowDmg and offHiDmg and not ns.IsSecret(offLowDmg) and not ns.IsSecret(offHiDmg) and offHiDmg > 0 then
				lastKnownWeaponDamage.offhand = { offLowDmg, offHiDmg }
			end
			if slot == "offhand" then
				if offLowDmg and offHiDmg and not ns.IsSecret(offLowDmg) and not ns.IsSecret(offHiDmg) then
					if offHiDmg > 0 then
						return offLowDmg, offHiDmg
					end
					return nil, nil
				end
			elseif lowDmg and hiDmg and not ns.IsSecret(lowDmg) and not ns.IsSecret(hiDmg) and hiDmg > 0 then
				return lowDmg, hiDmg
			end
		end
	end

	local cached = lastKnownWeaponDamage[slot]
	if cached then
		return cached[1], cached[2]
	end
	return nil, nil
end

function TooltipParser.CacheWeaponDamage()
	GetPlayerWeaponDamage("main")
	GetPlayerWeaponDamage("ranged")
end

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

	-- On boucle pour gérer les grands nombres (ex: 1 234 567) sans toucher aux décimales
	if clean:find("%d") then
		local rules = GetRules()
		local thousandPattern = (rules and rules.thousandPattern) or "(%d)[ ,](%d%d%d)"

		while true do
			local nextText, count = clean:gsub(thousandPattern, "%1%2")
			clean = nextText
			if count == 0 then
				break
			end
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
		ticks = details and details.ticks or nil,
		canCrit = not (details and details.canCrit == false),
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

-- Extrait la phrase courante après endIdx sans couper sur les décimales ("1,9" / "1.9")
local function ExtractSentenceAfter(lower, endIdx)
	local raw = lower:sub(endIdx + 1, endIdx + 140)
	local protected = raw:gsub("(%d),(%d)", "%1.%2")
	return protected:match("^(.-)%.%s") or protected:match("^(.-)%.$") or protected
end

-- Si un segment indique "toutes les X sec pendant Y sec", multiplie par le nombre de ticks
local function GetTickMultiplier(lower, startIdx, endIdx, rules)
	if not rules then
		return 1
	end

	local clause = NormalizeDurationUnits(ExtractSentenceAfter(lower, endIdx), rules)

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

	if rules.beforeIntervalDurationPatterns and startIdx and startIdx > 1 then
		local beforeRaw = lower:sub(math.max(1, startIdx - 72), startIdx - 1):gsub("(%d),(%d)", "%1.%2")
		local before = NormalizeDurationUnits(beforeRaw, rules)
		for _, pat in ipairs(rules.beforeIntervalDurationPatterns) do
			local duration, interval = before:match(pat)
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

	local after = NormalizeDurationUnits(ExtractSentenceAfter(lower, endIdx), rules)
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
		local beforeRaw = lower:sub(math.max(1, startIdx - 72), startIdx - 1):gsub("(%d),(%d)", "%1.%2")
		local before = NormalizeDurationUnits(beforeRaw, rules)
		for _, pat in ipairs(rules.beforeDurationPatterns) do
			dur = before:match(pat)
			if dur then
				break
			end
		end
	end

	if not dur and rules.beforeIntervalDurationPatterns and startIdx and startIdx > 1 then
		local beforeRaw = lower:sub(math.max(1, startIdx - 72), startIdx - 1):gsub("(%d),(%d)", "%1.%2")
		local before = NormalizeDurationUnits(beforeRaw, rules)
		for _, pat in ipairs(rules.beforeIntervalDurationPatterns) do
			local intervalDur = before:match(pat)
			if intervalDur then
				dur = intervalDur
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
			local _, tickDur = after:match(pat)
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
		local bestStart, bestEnd, bestMin, bestMax, bestKind, bestIsHealthPct

		for _, spec in ipairs(rules.chunkPatterns) do
			if not spec.requiresLineKind or spec.requiresLineKind == lineKind then
				local s, e, c1, c2 = lower:find(spec.pattern, pos)
				if s and spec.avoidNextWords then
					local tail = lower:sub(e + 1, e + 16)
					for _, badNext in ipairs(spec.avoidNextWords) do
						if tail:find(badNext) then
							s = nil
							break
						end
					end
				end
				if s and (not bestStart or s < bestStart) then
					bestStart = s
					bestEnd = e
					bestKind = spec.useLineKind and lineKind or spec.kind
					bestIsHealthPct = spec.isHealthPct and true or false
					bestMin = ParseDecimal(c1)
					bestMax = ParseDecimal(spec.range and c2 or c1)
					if spec.isWeaponPct then
						local lowDmg, hiDmg = GetPlayerWeaponDamage(spec.weaponSlot)
						local pct = ParseDecimal(c1)
						local bonus = ParseDecimal(c2) or 0
						if lowDmg and hiDmg and pct then
							bestMin = lowDmg * (pct / 100) + bonus
							bestMax = hiDmg * (pct / 100) + bonus
						else
							bestMin, bestMax = nil, nil
						end
					elseif spec.isWeaponBonus then
						local lowDmg, hiDmg = GetPlayerWeaponDamage(spec.weaponSlot)
						local bonus = ParseDecimal(c1) or 0
						if lowDmg and hiDmg then
							bestMin = lowDmg + bonus
							bestMax = hiDmg + bonus
						else
							bestMin, bestMax = nil, nil
						end
					elseif spec.isHealthPct and bestMin and bestMax then
						local maxHealth = GetPlayerMaxHealth()
						if maxHealth and maxHealth > 0 then
							bestMin = bestMin * (maxHealth / 100)
							bestMax = bestMax * (maxHealth / 100)
						else
							bestMin, bestMax = nil, nil
						end
					end
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

			local mult = GetTickMultiplier(lower, bestStart, bestEnd, rules)
			local segMin = bestMin * mult
			local segMax = bestMax * mult
			local segDuration = GetSegmentDuration(lower, bestStart, bestEnd, rules)

			local bucket = totals[bestKind]
			if not bucket then
				bucket = { min = 0, max = 0, directMin = 0, directMax = 0, dotMin = 0, dotMax = 0, duration = nil, canCrit = true }
				totals[bestKind] = bucket
			end
			if bestIsHealthPct then
				bucket.canCrit = false
			end
			bucket.min = bucket.min + segMin
			bucket.max = bucket.max + segMax

			if segDuration or mult > 1 then
				bucket.dotMin = bucket.dotMin + segMin
				bucket.dotMax = bucket.dotMax + segMax
				bucket.duration = bucket.duration or segDuration
				if mult > 1 then
					bucket.ticks = mult
				end
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

	local mult = GetTickMultiplier(rest, 1, endIdx, rules)
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
		ticks = chosenTier.ticks,
		canCrit = chosenTier.canCrit,
		cooldown = parsed.cooldown,
		comboTiers = parsed.comboTiers,
		comboMinTier = parsed.comboMinTier,
		comboMaxTier = parsed.comboMaxTier,
		activeComboPoints = usedCP,
	}
end

local function ParseCooldownText(rawText, rules)
	if not rawText or ns.IsSecret(rawText) or rawText == "" or not rules then
		return nil
	end

	local norm = NormalizeDurationUnits(NormalizeText(rawText):lower(), rules)
	if rules.cooldownSecPatterns then
		for _, pat in ipairs(rules.cooldownSecPatterns) do
			local val = norm:match(pat)
			if val then
				local sec = ParseDecimal(val)
				if sec and sec > 0 then
					return sec
				end
			end
		end
	end
	if rules.cooldownMinPatterns then
		for _, pat in ipairs(rules.cooldownMinPatterns) do
			local val = norm:match(pat)
			if val then
				local mins = ParseDecimal(val)
				if mins and mins > 0 then
					return mins * 60
				end
			end
		end
	end
	return nil
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
	local detectedCooldown = nil
	local contextKind = nil
	local contextSchool = nil
	local sawComboHint = false
	local comboTiers = {}
	local comboCount = 0
	local comboMinTier, comboMaxTier

	-- On commence à l'index 2 pour ignorer le titre du sort (ligne 1)
	for i = 2, #lines do
		local line = lines[i]
		if line and not ns.IsSecret(line) then
			if not detectedCooldown and i <= 5 then
				if line.rightText and not ns.IsSecret(line.rightText) then
					detectedCooldown = ParseCooldownText(line.rightText, rules)
				end
				if not detectedCooldown and line.leftText and not ns.IsSecret(line.leftText) then
					detectedCooldown = ParseCooldownText(line.leftText, rules)
				end
			end
			if line.leftText then
				if ns.IsSecret(line.leftText) then
					hadSecret = true
				else
					local normLine = NormalizeText(line.leftText)
					local lineHadCombo = false
					local lineHadParsed = false
					for subLine in normLine:gmatch("[^\r\n]+") do
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
							lineHadCombo = true
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
								lineHadParsed = true
							end
						end
					end
					if not lineHadCombo and not lineHadParsed and not firstParsed and normLine:find("[\r\n]") then
						firstParsed = TooltipParser.ParseLine((normLine:gsub("[\r\n]+", " ")))
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
			cooldown = detectedCooldown,
		}, true), hadSecret
	end

	if firstParsed and detectedCooldown and not firstParsed.cooldown then
		firstParsed.cooldown = detectedCooldown
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
