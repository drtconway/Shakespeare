-- Racial dialects: whole-word substitutions applied to a player's lines as
-- they speak them. The play data is never changed, so everyone shares the
-- same script. Keyed by the English race name from UnitRace.
local _, ns = ...

local MAX_BYTES = 255  -- one chat message

ns.DIALECTS = {
	-- WoW's trolls: "Ya mon", "Stay away from da voodoo".
	Troll = {
		label = "Troll speak",
		dropG = true,  -- "comin'" for "coming"
		tag = "mon",   -- added to the end of about one line in eight
		words = {
			the = "da", this = "dis", that = "dat", these = "dese", those = "dose",
			they = "dey", them = "dem", there = "dere", their = "deir", ["then"] = "den",  -- "then" is a Lua keyword
			think = "tink", thinking = "tinkin'", thought = "tought",
			thing = "ting", things = "tings",
			nothing = "nuttin'", something = "someting", anything = "anyting",
			everything = "everyting", with = "wit", without = "witout",
			mother = "mudda", father = "fadda", brother = "brudda", other = "udda",
			together = "togedda",
		},
	},
	-- WoW's dwarves: "Aye, lad", "Ye'll be wantin' a wee drink".
	Dwarf = {
		label = "Dwarf speak",
		dropG = true,
		words = {
			yes = "aye", you = "ye", your = "yer", yours = "yers", yourself = "yerself",
			my = "me", myself = "meself", little = "wee", small = "wee",
			boy = "lad", boys = "lads", girl = "lass", girls = "lasses",
			old = "auld", nothing = "nothin'",
		},
	},
}

-- Long -ing words that keep their g. Short ones (king, sing, bring) always do.
local KEEP_G = { spring = true, string = true }

local function MatchCase(original, replacement)
	if #original > 1 and original == original:upper() then
		return replacement:upper()
	elseif original:find("^%u") then
		return replacement:sub(1, 1):upper() .. replacement:sub(2)
	end
	return replacement
end

-- A stable stand-in for chance, so a line always comes out the same way.
local function Checksum(text)
	local n = 0
	for i = 1, #text, 7 do
		n = n + text:byte(i)
	end
	return n
end

-- The text as spoken in the given dialect (a key of ns.DIALECTS).
function ns.Accent(text, id)
	local dialect = ns.DIALECTS[id]
	if not dialect then return text end

	-- %a+ matches whole words only, so "other" never becomes "oda".
	local out = text:gsub("%a+", function(word)
		local lower = word:lower()
		local replacement = dialect.words[lower]
		if not replacement and dialect.dropG and #lower > 5
				and lower:sub(-3) == "ing" and not KEEP_G[lower] then
			replacement = lower:sub(1, -2) .. "'"
		end
		return replacement and MatchCase(word, replacement) or word
	end)

	if dialect.tag and Checksum(text) % 8 == 0 then
		local tagged, n = out:gsub("([%.!%?])$", ", " .. dialect.tag .. "%1")
		if n > 0 then out = tagged end
	end

	if #out > MAX_BYTES then return text end
	return out
end

-- The player's dialect, if they have turned it on and their race has one.
function ns.CurrentDialect()
	local db = ns.State()
	local race = select(2, UnitRace("player"))
	if db and db.useDialect and ns.DIALECTS[race] then return race end
end

-- A line as this player will speak it.
function ns.Speech(text)
	return ns.Accent(text, ns.CurrentDialect())
end
