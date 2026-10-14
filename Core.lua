-- Play state, casting, and keeping everyone in the group on the same line.
local addonName, ns = ...
ns.plays = ns.plays or {}

local PREFIX = "Shakespeare"
local PROMPT_DELAY = 5     -- seconds before other players may prompt
local CHAT_LOOKAHEAD = 6   -- spoken cues to search when matching /say text
local CAST_PATTERN = "^I will play the role of (.+)!$"

local db                   -- ShakespeareDB: { playId, pos, cast = { [roleId] = playerName } }
local lastDelivery = 0     -- GetTime() of the last delivered cue
local promptedAt = 0       -- GetTime() of the last prompt we sent
local myLastCue            -- index of the last cue we delivered

local function Print(...)
	print("|cffd4a017Shakespeare:|r", ...)
end
ns.Print = Print

-- Our name as other players' messages show it. With Forever's regional
-- unique names, UnitName returns a first name and a surname ("Staph",
-- "Pneumo") while messages come from "Staph Pneumo".
local function Me()
	local name, surname = UnitName("player")
	if surname and surname ~= "" then
		local consts = Constants and Constants.CharacterNameSeparatorConsts
		local separator = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
		name = name .. separator .. surname
	end
	return name
end
ns.Me = Me

local function Short(name)
	return name and Ambiguate(name, "none")
end

-- A name without any "-Realm" suffix, for comparing names.
local function BaseName(name)
	return (name:gsub("%-.*$", ""))
end

function ns.IsMe(name)
	return name ~= nil and BaseName(name) == BaseName(Me())
end

---------------------------------------------------------------------------
-- Play data helpers
---------------------------------------------------------------------------

function ns.Play()
	return db and ns.plays[db.playId]
end

function ns.State()
	return db
end

-- Identifies a play and the version of its data, so clients whose
-- generated files differ don't try to follow each other.
local function PlayKey(play)
	return play.id .. ":" .. #play.cues
end

function ns.Role(id)
	local play = ns.Play()
	if not play.roleById then
		play.roleById = {}
		for _, role in ipairs(play.roles) do
			play.roleById[role.id] = role
		end
	end
	return play.roleById[id]
end

function ns.RoleName(id)
	local role = ns.Role(id)
	return role and role.name or id
end

-- Index of the first cue at or after i that someone performs. Directions and
-- scene headings are skipped; returns #cues + 1 at the end of the play.
function ns.NextActionable(i)
	local cues = ns.Play().cues
	while i <= #cues and not cues[i].r do
		i = i + 1
	end
	return i
end

function ns.CurrentCue()
	local play = ns.Play()
	return play and play.cues[db.pos]
end

function ns.SceneIndex(pos)
	local scenes, index = ns.Play().scenes, 1
	for i, scene in ipairs(scenes) do
		if scene.start <= pos then index = i end
	end
	return index
end

-- Players cast in any of the cue's roles. Empty means the cue is open.
function ns.Performers(cue)
	local players = {}
	for _, role in ipairs(cue.r or {}) do
		local player = db.cast[role]
		if player then players[#players + 1] = player end
	end
	return players
end

-- True if one of the cue's roles is cast to us.
function ns.IsMine(cue)
	for _, player in ipairs(ns.Performers(cue)) do
		if ns.IsMe(player) then return true end
	end
	return false
end

-- True if we may deliver the cue: it is ours, or nobody has the role.
function ns.CanDeliver(cue)
	if not cue or not cue.r then return false end
	return ns.IsMine(cue) or #ns.Performers(cue) == 0
end

function ns.KnowsSpell(name)
	local id
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(name)
		id = info and info.spellID
	elseif GetSpellInfo then
		id = select(7, GetSpellInfo(name))
	end
	if not id then return false end
	return not IsPlayerSpell or IsPlayerSpell(id)
end

-- The first of a cue's spells that the player knows, if any.
function ns.CueSpell(cue)
	for _, spell in ipairs(cue.s or {}) do
		if ns.KnowsSpell(spell) then return spell end
	end
end

-- The player to prompt, if the current cue is overdue and belongs to
-- somebody else.
function ns.PromptTarget()
	local cue = ns.CurrentCue()
	if not cue or ns.CanDeliver(cue) then return end
	if GetTime() - math.max(lastDelivery, promptedAt) < PROMPT_DELAY then return end
	return ns.Performers(cue)[1]
end

function ns.Prompted()
	promptedAt = GetTime()
end

-- Weapons a cue can ask the player to wield (cue.w). class/subclass are
-- C_Item.GetItemInfoInstant's classID/subclassID; skill is the proficiency.
local WEAPONS = {
	dagger = { class = 2, subclass = 15, skill = 1180 },
}
local MAIN_HAND = 16

local function IsWeapon(item, weapon)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(item)
	return classID == weapon.class and subclassID == weapon.subclass
end

-- Macro lines that equip a weapon of the given kind into the main hand:
-- "" if one is already there, nil if the player has none they can use.
function ns.WieldMacro(kind)
	local weapon = WEAPONS[kind]
	if not weapon then return end
	if IsPlayerSpell and not IsPlayerSpell(weapon.skill) then return end

	local equipped = GetInventoryItemID("player", MAIN_HAND)
	if equipped and IsWeapon(equipped, weapon) then return "" end

	local level = UnitLevel("player")
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and IsWeapon(info.itemID, weapon) then
				local minLevel = select(5, C_Item.GetItemInfo(info.itemID))
				if not minLevel or minLevel <= level then
					return "/equipslot " .. MAIN_HAND .. " item:" .. info.itemID
				end
			end
		end
	end
end

-- The first of a cue's items (cue.u, e.g. drinks) the player has, unless
-- they have turned off "Use items". Items are consumed, so this is opt-out.
function ns.CueItem(cue)
	if not cue.u or db.useItems == false then return end
	local getCount = C_Item and C_Item.GetItemCount or GetItemCount
	for _, item in ipairs(cue.u) do
		local count = getCount(item)
		if count and count > 0 then return item end
	end
end

-- Whether the player can do anything for this cue's action.
function ns.CanAct(cue)
	return cue.e or ns.CueSpell(cue) or (cue.w and ns.WieldMacro(cue.w)) or ns.CueItem(cue)
end

local function HasAction(cue)
	return cue and cue.t and ns.CanAct(cue)
end

-- The spoken line whose emote or spell the Emote button performs: the line
-- we just delivered, until anyone delivers the next cue; otherwise the line
-- we are about to deliver.
function ns.EmoteCue()
	local last = myLastCue and ns.Play().cues[myLastCue]
	if HasAction(last) and ns.NextActionable(myLastCue + 1) == db.pos then
		return last
	end
	local cue = ns.CurrentCue()
	if HasAction(cue) and ns.CanDeliver(cue) then
		return cue
	end
end

---------------------------------------------------------------------------
-- Addon messages
---------------------------------------------------------------------------

local function Channel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
end

local function Send(command, arg, key)
	local channel, play = Channel(), ns.Play()
	if not channel or not (key or play) then return end
	local msg = (key or PlayKey(play)) .. " " .. command
	if arg then msg = msg .. " " .. arg end
	C_ChatInfo.SendAddonMessage(PREFIX, msg, channel)
end

---------------------------------------------------------------------------
-- State changes. Each local action is applied immediately and broadcast;
-- the matching receive handlers apply what other players send.
---------------------------------------------------------------------------

local function SetPos(i)
	db.pos = ns.NextActionable(math.max(1, i or 1))
	lastDelivery = GetTime()
	ns.Refresh()
end

local function ApplyCue(n)
	if not n then return end
	local nextPos = ns.NextActionable(n + 1)
	if nextPos <= db.pos then return end  -- stale or duplicate
	db.pos = nextPos
	lastDelivery = GetTime()
	ns.Refresh()
end

local function CastTo(role, player)
	if not ns.Role(role) then return end
	db.cast[role] = player
	ns.Refresh()
end

local function StartPlay(id)
	db.playId = id
	wipe(db.cast)
	myLastCue = nil
	SetPos(1)
end

-- Called after the deliver button has spoken the line.
function ns.Deliver(n)
	myLastCue = n
	ApplyCue(n)
	Send("CUE", n)
	local cue = ns.Play().cues[n]
	if cue.duel then ns.StageFight(cue) end
	if cue.yield then ns.Yield() end
end

---------------------------------------------------------------------------
-- Stage fights. A duel cue (cue.duel) challenges the player cast in
-- cue.at; their addon accepts a request from the expected challenger, and
-- the scripted loser forfeits on a yield cue. Both need "Stage duels" ticked.
-- Where duels aren't allowed (cities), the fight is still played as stage
-- combat: weapons drawn and a threat.
---------------------------------------------------------------------------

local DUEL_WINDOW = 4  -- cues before the current one a duel request may answer
local dueling = false

-- GetSheathState: 1 sheathed, 2 melee drawn, 3 ranged drawn.
function ns.DrawWeapon()
	if GetSheathState and ToggleSheath and GetSheathState() ~= 2 then
		ToggleSheath()
	end
end

-- Emote by slash command ("/lie"), usable in combat when macros are frozen.
function ns.Emote(slash)
	local token = hash_EmoteTokenList and hash_EmoteTokenList[slash:upper()]
	DoEmote(token or slash:sub(2):upper())
end

function ns.StageFight(cue)
	ns.DrawWeapon()
	DoEmote("THREATEN")
	local opponent = db.cast[cue.at]
	if db.stageDuels and opponent and not ns.IsMe(opponent) then
		StartDuel(opponent)
		dueling = true
	end
end

function ns.Yield()
	if dueling then
		ForfeitDuel()
		dueling = false
	end
end

-- Accept a duel only if the script calls for it: a recent duel cue aimed at
-- one of our roles, delivered by the challenger.
local function OnDuelRequested(challenger)
	local play = ns.Play()
	if not db.stageDuels or not play or not challenger then return end
	for i = math.max(1, db.pos - DUEL_WINDOW), math.min(#play.cues, db.pos) do
		local cue = play.cues[i]
		if cue.duel and ns.IsMe(db.cast[cue.at]) then
			for _, role in ipairs(cue.r) do
				local player = db.cast[role]
				if player and BaseName(player) == BaseName(challenger) then
					AcceptDuel()
					StaticPopup_Hide("DUEL_REQUESTED")
					dueling = true
					ns.DrawWeapon()
					return
				end
			end
		end
	end
end

function ns.Goto(i)
	SetPos(i)
	Send("GOTO", db.pos)
end

function ns.Cast(role)
	CastTo(role, Me())
	Send("CAST", role)
	SendChatMessage("I will play the role of " .. ns.RoleName(role) .. "!", "SAY")
end

function ns.Uncast(role)
	if not ns.IsMe(db.cast[role]) then return end
	db.cast[role] = nil
	ns.Refresh()
	Send("UNCAST", role)
end

function ns.SelectPlay(id)
	StartPlay(id)
	Send("PLAY")
end

-- Clear the cast and return to the start of the play, for the whole group.
function ns.Reset()
	ns.SelectPlay(db.playId)
	ns.Print("Reset " .. ns.Play().title .. ".")
end

StaticPopupDialogs.SHAKESPEARE_RESET = {
	text = "Reset Shakespeare?\n\nThis clears the cast and returns to the start of the play for everyone in your group.",
	button1 = YES,
	button2 = NO,
	OnAccept = function() ns.Reset() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ns.ConfirmReset()
	StaticPopup_Show("SHAKESPEARE_RESET")
end

StaticPopupDialogs.SHAKESPEARE_CHOOSE_PLAY = {
	text = "Perform %s?\n\nThis clears the cast and starts from the top for everyone in your group.",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, id)
		ns.SelectPlay(id)
		ns.Print("Now performing " .. ns.Play().title .. ".")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function ns.ConfirmPlay(id)
	StaticPopup_Show("SHAKESPEARE_CHOOSE_PLAY", ns.plays[id].title, nil, id)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function OnAddonMessage(prefix, msg, _, sender)
	if prefix ~= PREFIX then return end
	sender = Short(sender)
	if ns.IsMe(sender) then return end

	local key, command, arg = msg:match("^(%S+) (%S+) ?(.*)$")
	if not key then return end

	if command == "SYNC?" then
		-- The group leader answers with the play, position and cast.
		if not UnitIsGroupLeader("player") or not ns.Play() then return end
		Send("POS", db.pos)
		local byPlayer = {}
		for role, player in pairs(db.cast) do
			byPlayer[player] = byPlayer[player] and (byPlayer[player] .. "," .. role) or role
		end
		for player, roles in pairs(byPlayer) do
			Send("HOLD", player .. ";" .. roles)
		end
		return
	end

	local id = key:match("^[^:]+")
	local play = ns.plays[id]

	if command == "PLAY" or command == "POS" then
		if not play then
			Print(sender .. " is performing " .. id .. ", which you don't have.")
			return
		elseif PlayKey(play) ~= key then
			Print(sender .. " has a different version of " .. play.title .. ".")
			return
		end
		if command == "PLAY" then
			StartPlay(id)
			Print(sender .. " has chosen " .. play.title .. ".")
		else
			if db.playId ~= id then
				db.playId = id
				wipe(db.cast)
			end
			SetPos(tonumber(arg))
		end
		return
	end

	if not ns.Play() or PlayKey(ns.Play()) ~= key then return end

	if command == "CUE" then
		ApplyCue(tonumber(arg))
	elseif command == "GOTO" then
		SetPos(tonumber(arg))
	elseif command == "CAST" then
		CastTo(arg, sender)
	elseif command == "UNCAST" then
		if db.cast[arg] == sender then CastTo(arg, nil) end
	elseif command == "HOLD" then
		-- "Staph Pneumo;MACBETH,DON PEDRO": names and roles may contain spaces.
		local player, roles = arg:match("^(.-);(.+)$")
		for role in (roles or ""):gmatch("[^,]+") do
			CastTo(role, player)
		end
	end
end

local function Normalise(s)
	return (s:lower():gsub("[^%a]", ""))
end

-- Fallback for players without the addon: recognise role claims and lines
-- spoken in /say.
local function OnSay(text, sender)
	sender = Short(sender)
	local play = ns.Play()
	if ns.IsMe(sender) or not play then return end

	local name = text:match(CAST_PATTERN)
	if name then
		for _, role in ipairs(play.roles) do
			if role.name:lower() == name:lower() then CastTo(role.id, sender) end
		end
		return
	end

	local said, seen, i = Normalise(text), 0, db.pos
	while i <= #play.cues and seen < CHAT_LOOKAHEAD do
		local cue = play.cues[i]
		if cue.t then
			seen = seen + 1
			if not cue.norms then
				-- The line as anyone might say it: plain, or in a dialect.
				cue.norms = { [Normalise(cue.t)] = true }
				for id in pairs(ns.DIALECTS) do
					cue.norms[Normalise(ns.Accent(cue.t, id))] = true
				end
			end
			if cue.norms[said] then
				ApplyCue(i)
				return
			end
		end
		i = i + 1
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local wasInGroup = false
local events = CreateFrame("Frame")

events:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		ShakespeareDB = ShakespeareDB or {}
		db = ShakespeareDB
		db.cast = db.cast or {}
		db.autoEmote = db.autoEmote or false
		if not ns.plays[db.playId] then
			db.playId = ns.plays.muchado and "muchado" or next(ns.plays)
			db.pos = 1
			wipe(db.cast)
		end
		db.pos = ns.NextActionable(db.pos or 1)
		lastDelivery = GetTime()
		C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
		ns.CreateUI()
		ns.CreateMinimapButton()
		wasInGroup = IsInGroup()
		if wasInGroup then Send("SYNC?", nil, "-") end
	elseif event == "GROUP_ROSTER_UPDATE" then
		local inGroup = IsInGroup()
		if inGroup and not wasInGroup then Send("SYNC?", nil, "-") end
		wasInGroup = inGroup
	elseif event == "CHAT_MSG_ADDON" then
		OnAddonMessage(...)
	elseif event == "CHAT_MSG_SAY" then
		OnSay(...)
	elseif event == "DUEL_REQUESTED" then
		OnDuelRequested(...)
	elseif event == "DUEL_FINISHED" then
		dueling = false
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Last chance to change secure buttons before combat (e.g. a duel)
		-- freezes them.
		ns.EnterCombat()
	elseif event == "PLAYER_REGEN_ENABLED" or event == "BAG_UPDATE_DELAYED"
			or event == "PLAYER_EQUIPMENT_CHANGED" then
		-- Combat ended, or the weapons a cue could wield may have changed.
		ns.Refresh()
	end
end)

for _, event in ipairs({ "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON",
		"CHAT_MSG_SAY", "DUEL_REQUESTED", "DUEL_FINISHED", "PLAYER_REGEN_DISABLED",
		"PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED",
		"PLAYER_EQUIPMENT_CHANGED" }) do
	events:RegisterEvent(event)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_SHAKESPEARE1 = "/shakespeare"
SLASH_SHAKESPEARE2 = "/bard"
SlashCmdList.SHAKESPEARE = function(input)
	local command, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
	command = command:lower()

	if command == "" then
		ns.Toggle()
	elseif command == "plays" then
		for id, play in pairs(ns.plays) do
			Print(id .. " - " .. play.title)
		end
	elseif command == "play" then
		if ns.plays[rest] then
			ns.SelectPlay(rest)
		else
			Print("Unknown play '" .. rest .. "'. Try /bard plays.")
		end
	elseif command == "scene" then
		local act, scene = rest:match("^(%d+)%D+(%d+)$")
		for _, s in ipairs(ns.Play().scenes) do
			if s.act == tonumber(act) and s.scene == tonumber(scene) then
				ns.Goto(s.start)
				return
			end
		end
		Print("Usage: /bard scene <act> <scene>, e.g. /bard scene 2 3")
	elseif command == "reset" then
		ns.Reset()
	else
		Print("/bard - show or hide the teleprompter")
		Print("/bard plays - list the plays")
		Print("/bard play <id> - start a play for the whole group")
		Print("/bard scene <act> <scene> - jump to a scene")
		Print("/bard reset - clear the cast and start from the top")
	end
end
