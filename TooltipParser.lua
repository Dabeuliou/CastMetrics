local _, ns = ...

local TooltipParser = {}
ns.TooltipParser = TooltipParser

-- Normalise une ligne de tooltip pour faciliter le pattern matching en Lua :
--   1) supprime les balises de couleur WoW (|cAARRGGBB ... |r)
--   2) remplace l'espace insécable UTF-8 (\194\160) par un espace ASCII normal
--   3) fusionne les séparateurs de milliers (ex: "1 234" ou "1,234" -> "1234")
local function NormalizeText(text)
	local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	clean = clean:gsub("\194\160", " ")

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

-- Détermine si une ligne décrit des dégâts ou des soins
local function DetectLineKind(lowerText)
	-- Vérification des soins en premier (FR et EN)
	local padded = lowerText .. " "
	if
		padded:find("points? de vie")
		or padded:find("soigne")
		or padded:find("soins")
		or padded:find("heals?[%s%p]")
		or padded:find("healing")
		or padded:find("restores?%s+%d+.-health")
	then
		return "heal"
	end

	-- Vérification des dégâts (FR et EN)
	-- Attention Lua/UTF-8 : on n'utilise jamais d[ée]g[âa]ts car [...] en Lua ne matche qu'un seul octet,
	-- alors que 'é' et 'â' font 2 octets en UTF-8. On teste les mots littéraux complets.
	if
		lowerText:find("dégât")
		or lowerText:find("Dégât")
		or lowerText:find("degat")
		or lowerText:find("damage")
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
	{ school = 1, words = { "physique", "physical damage", "de l'arme", "weapon damage" } },
}

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
	{ pattern = "soigne[^%d%.]*(%d+)%s+à%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
	{ pattern = "pour%s+(%d+)%s+à%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
	-- Intervalles EN
	{ pattern = "(%d+)%s+to%s+(%d+)[^%.]-damage", kind = "damage", range = true },
	{ pattern = "heals?[^%d%.]*(%d+)%s+to%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
	{ pattern = "for%s+(%d+)%s+to%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
	{ pattern = "another%s+(%d+)%s+to%s+(%d+)", kind = "heal", range = true, requiresLineKind = "heal" },
	-- Valeurs uniques FR
	{ pattern = "(%d+)%s+points?%s+de%s+dégâts?", kind = "damage", range = false },
	{ pattern = "(%d+)%s+points?%s+de%s+degats?", kind = "damage", range = false },
	{ pattern = "(%d+)%s+points?%s+de%s+vie", kind = "heal", range = false },
	{ pattern = "(%d+)%s+points?%s+supplémentaires", kind = "heal", range = false, requiresLineKind = "heal" },
	{ pattern = "pour%s+(%d+)%s+points?", kind = "heal", range = false, requiresLineKind = "heal" },
	{ pattern = "soigne[^%d%.]*(%d+)", kind = "heal", range = false, requiresLineKind = "heal" },
	-- Valeurs uniques EN
	{ pattern = "(%d+)%s+%a+%s+damage", kind = "damage", range = false },
	{ pattern = "(%d+)%s+damage", kind = "damage", range = false },
	{ pattern = "for%s+(%d+)%s+health", kind = "heal", range = false, requiresLineKind = "heal" },
	{ pattern = "heals?[^%d%.]*(%d+)", kind = "heal", range = false, requiresLineKind = "heal" },
	{ pattern = "another%s+(%d+)", kind = "heal", range = false, requiresLineKind = "heal" },
}

-- Si un segment indique "toutes les X sec pendant Y sec", multiplie par le nombre de ticks
local function GetTickMultiplier(lower, endIdx)
	local after = lower:sub(endIdx + 1, endIdx + 64)
	local clause = after:match("^[^%.,]+") or after

	local interval, duration = clause:match("toutes les%s+(%d+)%s+sec.-pendant%s+(%d+)%s+sec")
	if not interval then
		interval, duration = clause:match("every%s+(%d+)%s+sec.-for%s+(%d+)%s+sec")
	end

	if interval and duration then
		local iv = tonumber(interval)
		local dur = tonumber(duration)
		if iv and dur and iv > 0 then
			local ticks = math.floor((dur / iv) + 0.5)
			if ticks >= 1 and ticks <= 60 then
				return ticks
			end
		end
	end

	local perSecDur = clause:match("toutes les%s+sec.-pendant%s+(%d+)%s+sec")
		or clause:match("par sec.-pendant%s+(%d+)%s+sec")
		or clause:match("every%s+sec.-for%s+(%d+)%s+sec")
		or clause:match("per sec.-for%s+(%d+)%s+sec")
	if perSecDur then
		local dur = tonumber(perSecDur)
		if dur and dur >= 1 and dur <= 60 then
			return dur
		end
	end

	return 1
end

-- Détecte si le segment courant est périodique ("en 12 sec" / "over 12 sec" / "pendant 12 sec")
-- sans déborder sur un éventuel segment suivant (on s'arrête avant le prochain chiffre s'il n'est pas la durée)
local function GetSegmentDuration(lower, endIdx)
	local after = lower:sub(endIdx + 1, endIdx + 64)
	local dur = after:match("^[^%.,%d]*en%s+(%d+)%s+sec")
		or after:match("^[^%.,%d]*pendant%s+(%d+)%s+sec")
		or after:match("^[^%.,%d]*over%s+(%d+)%s+sec")
		or after:match("^[^%.,%d]*for%s+(%d+)%s+sec")
	if dur then
		local num = tonumber(dur)
		if num and num > 0 and num <= 120 then
			return num
		end
	end

	local _, tickDur = after:match("^[^%.,%d]*toutes les%s+(%d+)%s+sec.-pendant%s+(%d+)%s+sec")
	if not tickDur then
		_, tickDur = after:match("^[^%.,%d]*every%s+(%d+)%s+sec.-for%s+(%d+)%s+sec")
	end
	if tickDur then
		local num = tonumber(tickDur)
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
					bestKind = spec.kind
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

	-- 2. Fallback générique si la ligne contient un mot-clé mais aucun motif standard n'a matché
	local fallbackDetails = { school = lineSchool }
	local minV, maxV = lower:match("(%d+)%s+à%s+(%d+)")
	if not minV then
		minV, maxV = lower:match("(%d+)%s+to%s+(%d+)")
	end
	if not minV then
		minV, maxV = lower:match("(%d+)%s*%-%s*(%d+)")
	end
	if minV then
		return MakeResult(minV, maxV, lineKind, fallbackDetails)
	end

	for num, suffix in lower:gmatch("(%d+)([%s%%a]*)") do
		local trimmed = suffix:match("^%s*(%S*)") or ""
		local isUnit = trimmed:find("^%%")
			or trimmed:find("^sec")
			or trimmed:find("^min")
			or trimmed:find("^yd")
			or trimmed:find("^mana")
		if not isUnit then
			return MakeResult(num, num, lineKind, fallbackDetails)
		end
	end

	return nil
end

-- Parcourt un tableau de lignes de tooltip (TooltipData.lines) et retourne (parsedResult, hadSecret)
function TooltipParser.ParseLines(lines)
	if not lines or ns.IsSecret(lines) then
		return nil, true
	end

	local hadSecret = false
	-- On commence à l'index 2 pour ignorer le titre du sort (ligne 1)
	for i = 2, #lines do
		local line = lines[i]
		if line and not ns.IsSecret(line) and line.leftText then
			if ns.IsSecret(line.leftText) then
				hadSecret = true
			else
				local parsed = TooltipParser.ParseLine(line.leftText)
				if parsed then
					return parsed, hadSecret
				end
			end
		end
	end

	return nil, hadSecret
end

-- Interroge C_TooltipInfo.GetAction(slot) et retourne (parsedResult, tooltipSpellID, hadSecret)
function TooltipParser.GetActionValues(slot)
	if not C_TooltipInfo or not C_TooltipInfo.GetAction then
		return nil, nil, false
	end

	local tooltipData = C_TooltipInfo.GetAction(slot)
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
