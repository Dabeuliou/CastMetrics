---@diagnostic disable
-- Standalone Lua 5.1 test runner for CastMetrics TooltipParser + Locales.
-- Usage: lua tests/run_tests.lua

local currentLocale = "enUS"
local currentComboPoints = 3

_G["GetLocale"] = function()
	return currentLocale
end

_G["Enum"] = {
	PowerType = {
		ComboPoints = 4,
	},
}

_G["UnitPower"] = function(_, powerType)
	if powerType == _G["Enum"].PowerType.ComboPoints then
		return currentComboPoints
	end
	return 100
end

_G["UnitHealthMax"] = function()
	return 10000
end

_G["issecretvalue"] = function(_)
	return false
end

local ns = {}

local function loadAddonFile(relPath)
	local chunk, err = loadfile(relPath)
	if not chunk then
		error("Failed to load " .. relPath .. ": " .. tostring(err))
	end
	return chunk("CastMetrics", ns)
end

local function loadForLocale(locale)
	currentLocale = locale
	ns = {}
	loadAddonFile("Locales/Locale.lua")
	loadAddonFile("Locales/enUS.lua")
	if locale ~= "enUS" then
		loadAddonFile("Locales/" .. locale .. ".lua")
	end
	loadAddonFile("TooltipParser.lua")
end

local corpus = dofile("tests/corpus_data.lua")
local byLocale = {}
for _, entry in ipairs(corpus) do
	byLocale[entry.locale] = byLocale[entry.locale] or {}
	table.insert(byLocale[entry.locale], entry)
end

local totalPassed, totalFailed = 0, 0

for _, loc in ipairs({ "enUS", "frFR", "deDE", "esES" }) do
	local entries = byLocale[loc] or {}
	loadForLocale(loc)
	local passed, failed = 0, 0
	local failures = {}

	for _, entry in ipairs(entries) do
		local lines = {}
		for _, txt in ipairs(entry.lines) do
			table.insert(lines, { leftText = txt })
		end
		local parsed = ns.TooltipParser.ParseLines(lines)
		if parsed and parsed.avg and parsed.avg > 0 then
			passed = passed + 1
		else
			failed = failed + 1
			table.insert(failures, entry)
		end
	end

	totalPassed = totalPassed + passed
	totalFailed = totalFailed + failed
	print(string.format("[%s] %d/%d parsed (%d missed)", loc, passed, #entries, failed))
	for _, entry in ipairs(failures) do
		print(string.format("  MISS %d (%s / %s):", entry.spellID, entry.class, entry.name))
		for idx, txt in ipairs(entry.lines) do
			print(string.format("    [%d] %s", idx, txt))
		end
	end
end

print(string.format("TOTAL: %d passed, %d missed", totalPassed, totalFailed))
if totalFailed > 0 then
	os.exit(1)
end
