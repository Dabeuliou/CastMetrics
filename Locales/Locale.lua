local _, ns = ...

local LOCALE_ALIASES = {
	enGB = "enUS",
	esMX = "esES",
	ptPT = "ptBR",
}

local rawLocale = (GetLocale and GetLocale()) or "enUS"
ns.LOCALE = LOCALE_ALIASES[rawLocale] or rawLocale

ns.Locales = {}

local fallbackUI = {}
local activeUI = {}

-- Table de traduction avec repli automatique vers enUS via métatable (__index)
ns.L = setmetatable({}, {
	__index = function(_, key)
		local val = activeUI[key]
		if val ~= nil then
			return val
		end
		local fb = fallbackUI[key]
		if fb ~= nil then
			return fb
		end
		return key
	end,
})

function ns.RegisterLocale(localeCode, uiStrings, parserRules)
	ns.Locales[localeCode] = {
		ui = uiStrings,
		parser = parserRules,
	}

	if localeCode == "enUS" and uiStrings then
		fallbackUI = uiStrings
	end
	if localeCode == ns.LOCALE and uiStrings then
		activeUI = uiStrings
	end
end

function ns.GetParserLocale()
	local entry = ns.Locales[ns.LOCALE]
	if entry and entry.parser then
		return entry.parser
	end
	return ns.Locales.enUS and ns.Locales.enUS.parser
end
