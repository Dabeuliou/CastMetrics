local _, ns = ...

local TooltipParser = {}
ns.TooltipParser = TooltipParser

-- Normalise une ligne de tooltip pour faciliter le pattern matching en Lua :
--   1) supprime les balises de couleur/texture/atlas WoW (|cAARRGGBB, |cnNAME:, |r, |T...|t, |A...|a)
--   2) résout les balises de pluriel (|4singulier:pluriel; -> pluriel) et |n -> \n
--   3) remplace les espaces insécables UTF-8 (\194\160 et \226\128\175) par un espace ASCII normal
--   4) fusionne les séparateurs de milliers (ex: "1 234" ou "1,234" -> "1234")
local function NormalizeText(text)
	local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]+:", ""):gsub("|r", "")
	clean = clean:gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", "")
	clean = clean:gsub("|4[^:;]+:([^;]+);", "%1")
	clean = clean:gsub("|n", "\n")
	clean = clean:gsub("\194\160", " "):gsub("\226\128\175", " ")

	-- On boucle pour gérer les grands nombres (ex: 1 234 567) sans toucher aux décimales ("1,5 sec")
	while true do
		local nextText, count = clean:gsub("(%d)[ ,](%d%d%d)", "%1%2")
		clean = nextText
		if count == 0 then
			break
		end
	end

	return clean
end

TooltipParser.NormalizeText = NormalizeText

-- Détermine si une ligne décrit des dégâts ou des soins réels (et non un buff de stats / changeforme)
local function DetectLineKind(lowerText)
	-- Ignore la nourriture et les boissons ("vous devez rester assis" / "must remain seated")
	if lowerText:find("assis", 1, true) or lowerText:find("seated", 1, true) then
		return nil
	end

	-- Vérification des soins (FR et EN) : un nombre suivi de "points de vie", ou un verbe de soin explicite
	local padded = lowerText .. " "
	if
		padded:find("%d+%s+points?%s+de%s+vie")
		or padded:find("soigne")
		or padded:find("soins")
		or padded:find("heals?[%s%p]")
		or padded:find("healing")
		or padded:find("restores?%s+%d+.-health")
	then
		return "heal"
	end

	-- Vérification des dégâts (FR et EN) : un nombre suivi de "points de dégâts" / "damage", ou attaque d'arme
	if
		lowerText:find("%d+%s+points?%s+de%s+dégât")
		or lowerText:find("%d+%s+points?%s+de%s+degat")
		or lowerText:find("dégâts? de l'arme")
		or lowerText:find("%d+[^%.]-damage")
		or lowerText:find("weapon damage")
	then
		return "damage"
	end

	return nil
end

local SCHOOL_PATTERNS = {
	{ school = 2, words = { "du sacré", "holy damage" } },
	{ school = 3, words = { "de feu", "fire damage" } },
	{ school = 4, words = { "de nature", "nature damage" } },
	{ school = 5, words = { "de givre", "frost damage" } },
	{ school = 6, words = { "d'ombre", "shadow damage" } },
	{ school = 7, words = { "des arcanes", "arcane damage" } },
	{ school = 1, words = { "physique", "saignement", "physical damage", "bleed", "de l'arme", "weapon damage" } },
}

local function DetectContextKind(lowerText)
	if lowerText:find("assis", 1, true) or lowerText:find("seated", 1, true) then
		return nil
	end
	local padded = lowerText .. " "
	if
		padded:find("soigne")
		or padded:find("soins")
		or padded:find("points?%s+de%s+vie")
		or padded:find("heals?[%s%p]")
		or padded:find("healing")
		or padded:find("restores?[%s%p].-health")
	then
		return "heal"
	end
	if
		padded:find("dégât")
		or padded:find("degat")
		or padded:find("damage")
		or padded:find("inflige")
		or padded:find("deals?[%s%p]")
	then
		return "damage"
	end
	return nil
end

local function DetectSchool(lowerText)
	for _, entry in ipairs(SCHOOL_PATTERNS) do
		for _, word in ipairs(entry.words) do
			if lowerText:find(word, 1, true) then
				return entry.school
			end
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

-- Liste ordonnée de motifs pour capturer tous les segments de dégâts/soins d'une ligne
-- (ex: dégâts directs + DoT sur Éclat lunaire, soin direct + HoT sur Rétablissement)
local CHUNK_PATTERNS = {
	-- Intervalles FR (toujours placés avant les motifs de valeur unique pour éviter une troncature)
	{ pattern = "(%d+)%s+à%s+(%d+)%s+points?%s+de%s+dégâts?", kind = "damage", range = true },
	{ pattern = "(%d+)%s+à%s+(%d+)%s+points?%s+de%s+degats?", kind = "damage", range = true },
	{ pattern = "(%d+)%s+à%s+(%d+)%s+points?%s+de%s+vie", kind = "heal", range = true },
	{ pattern = "(%d+)%s+à%s+(%d+)%s+points?%s+supplémentaires", useLineKind = true, range = true },
	{ pattern = "(%d+)%s+à%s+(%d+)%s+supplémentaires", useLineKind = true, range = true },
	{ pattern = "soigne[^%d%.]*(%d+)%s+à%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
	{ pattern = "pour%s+(%d+)%s+à%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
	-- Intervalles EN
	{ pattern = "(%d+)%s+to%s+(%d+)[^%.]-damage", kind = "damage", range = true },
	{ pattern = "heals?[^%d%.]*(%d+)%s+to%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
	{ pattern = "for%s+(%d+)%s+to%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
	{ pattern = "another%s+(%d+)%s+to%s+(%d+)", useLineKind = true, range = true },
	-- Valeurs uniques FR
	{ pattern = "(%d+)%s+points?%s+de%s+dégâts?", kind = "damage", range = false },
	{ pattern = "(%d+)%s+points?%s+de%s+degats?", kind = "damage", range = false },
	{ pattern = "dégâts? de l'arme[^%d]*plus%s+(%d+)", kind = "damage", range = false },
	{ pattern = "(%d+)%s+points?%s+de%s+vie", kind = "heal", range = false },
	{ pattern = "(%d+)%s+points?%s+supplémentaires", useLineKind = true, range = false },
	{ pattern = "(%d+)%s+supplémentaires", useLineKind = true, range = false },
	{ pattern = "pour%s+(%d+)%s+points?", kind = "heal", range = false, requiresLineKind = "heal" },
	{ pattern = "soigne[^%d%.]*(%d+)", kind = "heal", range = false, requiresLineKind = "heal" },
	-- Valeurs uniques EN
	{ pattern = "(%d+)%s+%a+%s+damage", kind = "damage", range = false },
	{ pattern = "(%d+)%s+damage", kind = "damage", range = false },
	{ pattern = "weapon damage[^%d]*plus%s+(%d+)", kind = "damage", range = false },
	{ pattern = "for%s+(%d+)%s+health", kind = "heal", range = false, requiresLineKind = "heal" },
	{ pattern = "heals?[^%d%.]*(%d+)", kind = "heal", range = false, requiresLineKind = "heal" },
	{ pattern = "another%s+(%d+)", useLineKind = true, range = false },
}

local function ParseDecimal(str)
	if not str then
		return nil
	end
	return tonumber((str:gsub(",", ".")))
end

-- Normalise "4 s" / "10,4 s" -> "4 sec" / "10,4 sec" sans toucher aux mots comme "spells"
local function NormalizeDurationUnits(text)
	return (text .. " "):gsub("(%d)%s+s([%s%p])", "%1 sec%2")
end

-- Si un segment indique "toutes les X sec pendant Y sec", multiplie par le nombre de ticks (entiers ou décimaux sous Hâte)
local function GetTickMultiplier(lower, endIdx)
	local after = NormalizeDurationUnits(lower:sub(endIdx + 1, endIdx + 64))
	local clause = after:match("^[^%.,]+") or after

	local interval, duration = clause:match("toutes les%s+([%d%.,]+)%s+sec.-pendant%s+([%d%.,]+)%s+sec")
	if not interval then
		interval, duration = clause:match("every%s+([%d%.,]+)%s+sec.-for%s+([%d%.,]+)%s+sec")
	end

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

	local perSecDur = clause:match("toutes les%s+sec.-pendant%s+([%d%.,]+)%s+sec")
		or clause:match("par sec.-pendant%s+([%d%.,]+)%s+sec")
		or clause:match("every%s+sec.-for%s+([%d%.,]+)%s+sec")
		or clause:match("per sec.-for%s+([%d%.,]+)%s+sec")
	if perSecDur then
		local dur = ParseDecimal(perSecDur)
		if dur and dur >= 1 and dur <= 60 then
			return dur
		end
	end

	return 1
end

-- Détecte si le segment courant est périodique ("en 12 sec" / "en 10,4 s" / "over 10.4 sec" / "pendant 21 s")
-- sans déborder sur un effet secondaire (ex: "118 et Déchirure pendant 4 s")
local function GetSegmentDuration(lower, endIdx)
	local after = NormalizeDurationUnits(lower:sub(endIdx + 1, endIdx + 64))
	local dur = after:match("^[^%.,%d]*en%s+([%d%.,]+)%s+sec")
		or after:match("^[^%.,%d]*over%s+([%d%.,]+)%s+sec")

	if not dur then
		local beforePendant, pendantDur = after:match("^([^%.,%d]*)pendant%s+([%d%.,]+)%s+sec")
		if not beforePendant then
			beforePendant, pendantDur = after:match("^([^%.,%d]*)for%s+([%d%.,]+)%s+sec")
		end
		if pendantDur and beforePendant then
			local paddedPrefix = " " .. beforePendant .. " "
			if not paddedPrefix:find("%set%s+") and not paddedPrefix:find("%sand%s+") then
				dur = pendantDur
			end
		end
	end

	if dur then
		local num = ParseDecimal(dur)
		if num and num > 0 and num <= 120 then
			return num
		end
	end

	local _, tickDur = after:match("^[^%.,%d]*toutes les%s+([%d%.,]+)%s+sec.-pendant%s+([%d%.,]+)%s+sec")
	if not tickDur then
		_, tickDur = after:match("^[^%.,%d]*every%s+([%d%.,]+)%s+sec.-for%s+([%d%.,]+)%s+sec")
	end
	if tickDur then
		local num = ParseDecimal(tickDur)
		if num and num > 0 and num <= 120 then
			return num
		end
	end

	return nil
end

-- Extrait min/max (en cumulant direct + DoT/HoT) depuis une ligne de texte
function TooltipParser.ParseLine(rawText)
	-- IMPORTANT (WoW Forever / Midnight) : toujours tester ns.IsSecret() AVANT toute comparaison (==, etc.)
	if not rawText or ns.IsSecret(rawText) or rawText == "" then
		return nil
	end

	local text = NormalizeText(rawText)
	local lower = text:lower()
	local lineKind = DetectLineKind(lower)
	if not lineKind then
		return nil
	end
	local lineSchool = DetectSchool(lower)

	-- 1. Parcours séquentiel de gauche à droite pour cumuler tous les segments (ex: direct + DoT)
	local totals = {}
	local primaryKind = nil
	local pos = 1

	while pos <= #lower do
		local bestStart, bestEnd, bestMin, bestMax, bestKind

		for _, spec in ipairs(CHUNK_PATTERNS) do
			if not spec.requiresLineKind or spec.requiresLineKind == lineKind then
				local s, e, c1, c2 = lower:find(spec.pattern, pos)
				if s and (not bestStart or s < bestStart) then
					bestStart = s
					bestEnd = e
					bestKind = spec.useLineKind and lineKind or spec.kind
					bestMin = tonumber(c1)
					bestMax = tonumber(spec.range and c2 or c1)
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

			local mult = GetTickMultiplier(lower, bestEnd)
			local segMin = bestMin * mult
			local segMax = bestMax * mult
			local segDuration = GetSegmentDuration(lower, bestEnd)

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
local function ParseComboTierLine(rawSubLine, contextKind, contextSchool)
	local text = NormalizeText(rawSubLine)
	local lower = text:lower()
	local cpStr, rest = lower:match("^%s*(%d+)%s+points?%s*:%s*(.+)$")
	if not cpStr or not rest then
		return nil, nil
	end

	local cp = tonumber(cpStr)
	if not cp or cp < 1 or cp > 10 then
		return nil, nil
	end

	local parsed = TooltipParser.ParseLine(rest)
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
	local s1, e1, a, b = rest:find("^(%d+)%s+à%s+(%d+)")
	if not s1 then
		s1, e1, a, b = rest:find("^(%d+)%s+to%s+(%d+)")
	end
	if not s1 then
		s1, e1, a, b = rest:find("^(%d+)%s*%-%s*(%d+)")
	end
	if s1 then
		minVal, maxVal, endIdx = tonumber(a), tonumber(b), e1
	else
		local s2, e2, v = rest:find("^(%d+)")
		if s2 then
			minVal, maxVal, endIdx = tonumber(v), tonumber(v), e2
		end
	end

	if not minVal or not maxVal or not endIdx then
		return nil, nil
	end
	if maxVal < minVal then
		minVal, maxVal = maxVal, minVal
	end

	local mult = GetTickMultiplier(rest, endIdx)
	local segMin = minVal * mult
	local segMax = maxVal * mult
	local segDuration = GetSegmentDuration(rest, endIdx)

	local details = {
		school = DetectSchool(rest) or contextSchool,
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
					if lowerSub:find("combo", 1, true) then
						sawComboHint = true
					end
					if not contextKind then
						contextKind = DetectContextKind(lowerSub)
					end
					if not contextSchool then
						contextSchool = DetectSchool(lowerSub)
					end

					local cp, tierResult = ParseComboTierLine(subLine, contextKind, contextSchool)
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
