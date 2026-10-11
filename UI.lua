-- The teleprompter window, the deliver and prompt buttons, and the cast list.
local _, ns = ...

local WIDTH, HEIGHT = 660, 440
local ROWS = 8
local PROMPT_EMOTES = { "/poke", "/cough", "/sigh" }
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local WINDOW_BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local ROW_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

BINDING_HEADER_SHAKESPEARE = "Shakespeare"
_G["BINDING_NAME_CLICK ShakespeareDeliverButton:LeftButton"] = "Deliver the next line"

local DROPDOWN_ARROW = " |TInterface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up:18|t"

local frame, script, rows, deliver, emote, prompt, castPanel, titleButton, playMenu
local castRows = {}

-- When the ActionButtonUseKeyDown CVar exists, secure buttons act on either
-- the down or the up half of a click. Only react to the half that acts.
local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
local hasKeyDownCVar = getCVar("ActionButtonUseKeyDown") ~= nil
local function ClickIsLive(down)
	if not hasKeyDownCVar then return true end
	return (down and true or false) == GetCVarBool("ActionButtonUseKeyDown")
end

---------------------------------------------------------------------------
-- Text for a cue
---------------------------------------------------------------------------

local function SpeakerText(cue)
	local state, names = ns.State(), {}
	for _, role in ipairs(cue.r) do
		local player = state.cast[role]
		local name = ns.RoleName(role)
		if player then name = name .. " |cff9d9d9d(" .. player .. ")|r" end
		names[#names + 1] = name
	end
	local color = ns.IsMine(cue) and "|cff40ff40" or "|cffffd100"
	return color .. table.concat(names, " & ") .. "|r"
end

local function ActionText(cue)
	local parts = {}
	if cue.s then parts[#parts + 1] = table.concat(cue.s, "/") end
	if cue.e then parts[#parts + 1] = cue.e end
	if #parts == 0 then return "" end
	local text = table.concat(parts, " or ")
	if cue.at then text = text .. " at " .. ns.RoleName(cue.at) end
	return "  |cff66bbff<" .. text .. ">|r"
end

local function DirectionText(d)
	return "|cffaaaaaa[" .. d .. "]|r"
end

local function CueText(cue)
	if cue.h then
		return "|cffd4a017" .. cue.d .. "|r"
	elseif cue.t then
		local speaker = SpeakerText(cue)
		if cue.d then speaker = speaker .. " " .. DirectionText(cue.d) end
		return speaker .. "\n" .. cue.t .. ActionText(cue)
	elseif cue.r then
		return SpeakerText(cue) .. "\n" .. DirectionText(cue.d) .. ActionText(cue)
	end
	return DirectionText(cue.d)
end

-- The secure macro that performs the first of a cue's spells the player
-- knows, or else its emote. If the cue is directed at a role, target that
-- role's player for it and then restore the previous target.
local function ActionMacro(cue)
	local spell = ns.CueSpell(cue)
	local action = spell and ("/cast " .. spell) or cue.e
	if not action then return "" end
	if not cue.at then return action end

	local player = ns.State().cast[cue.at]
	if player and player ~= ns.Me() then
		return "/target " .. player .. "\n" .. action .. "\n/targetlasttarget"
	end
	-- Nobody to aim at: don't aim it at whoever happens to be targeted.
	return "/cleartarget\n" .. action .. "\n/targetlasttarget"
end

local function ActionLabel(cue)
	return ns.CueSpell(cue) or cue.e
end

-- What the deliver button does besides speaking. Stage business (no words)
-- always performs its action; spoken lines only with auto emotes on.
local function DeliverMacro(cue)
	if not cue.t or ns.State().autoEmote then return ActionMacro(cue) end
	return ""
end

---------------------------------------------------------------------------
-- Refreshing
---------------------------------------------------------------------------

-- Secure buttons can only be changed out of combat; Core calls Refresh
-- again on PLAYER_REGEN_ENABLED.
local function RefreshSecure()
	if not frame or InCombatLockdown() then return end
	local cue = ns.CurrentCue()
	local canDeliver = ns.CanDeliver(cue)

	deliver:SetAttribute("macrotext", canDeliver and DeliverMacro(cue) or "")
	deliver:SetEnabled(canDeliver)

	local emoteCue = ns.EmoteCue()
	emote:SetAttribute("macrotext", emoteCue and ActionMacro(emoteCue) or "")
	emote:SetEnabled(emoteCue ~= nil)
	emote:SetText(emoteCue and ActionLabel(emoteCue) or "Emote")
	if not cue then
		deliver:SetText("Finis")
	elseif not canDeliver then
		deliver:SetText("Waiting...")
	elseif not cue.t then
		deliver:SetText("Perform")
	else
		deliver:SetText(ns.IsMine(cue) and "Speak" or "Speak (open)")
	end

	local target = ns.PromptTarget()
	if target ~= prompt.target then
		prompt.target = target
		if target then
			local emote = PROMPT_EMOTES[math.random(#PROMPT_EMOTES)]
			prompt:SetAttribute("macrotext", "/target " .. target .. "\n" .. emote)
			prompt:SetText("Prompt " .. target)
		end
		prompt:SetShown(target ~= nil)
	end
end

local function RefreshScript()
	local play, state = ns.Play(), ns.State()
	local cues, pos = play.cues, state.pos

	frame.title:SetText(play.title .. DROPDOWN_ARROW)
	titleButton:SetSize(frame.title:GetStringWidth() + 16, 24)
	local scene = play.scenes[ns.SceneIndex(pos)]
	-- The scene's heading cue, e.g. "Act 1, Scene 2. A room…" or "Act 2, Prologue".
	frame.scene:SetText(scene and cues[scene.start].d or "")

	-- Start at the last spoken line, so the cue line is always visible.
	local first = pos - 1
	while first > 1 and not cues[first].t do
		first = first - 1
	end
	first = math.max(first, 1)

	for i, row in ipairs(rows) do
		local index = first + i - 1
		local cue = cues[index]
		if cue then
			row.text:SetText(CueText(cue))
			row:SetHeight(row.text:GetStringHeight() + 12)
			-- Dim lines already delivered; directions leading up to the
			-- current cue stay bright because they are happening now.
			row:SetAlpha((index < pos and cue.r) and 0.5 or 1)
			if index == pos then
				row:SetBackdropColor(0.25, 0.2, 0, 0.6)
				if ns.CanDeliver(cue) then
					row:SetBackdropBorderColor(1, 0.82, 0, 1)
				else
					row:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
				end
			else
				row:SetBackdropColor(0, 0, 0, 0)
				row:SetBackdropBorderColor(0, 0, 0, 0)
			end
			row:Show()
		else
			row:Hide()
		end
	end
end

local function RefreshCast()
	local play, state = ns.Play(), ns.State()
	for i, role in ipairs(play.roles) do
		local row = castRows[i] or ns.CreateCastRow(i)
		row.role = role
		row.label:SetText(role.name .. " |cff9d9d9d(" .. role.cues .. ")|r")
		local player = state.cast[role.id]
		if player == ns.Me() then
			row.player:SetText("|cff40ff40" .. player .. "|r")
		else
			row.player:SetText(player or "|cff9d9d9d-|r")
		end
		row:Show()
	end
	for i = #play.roles + 1, #castRows do
		castRows[i]:Hide()
	end
	castPanel:SetHeight(48 + #play.roles * 16)
end

function ns.Refresh()
	if not frame then return end
	RefreshScript()
	RefreshCast()
	RefreshSecure()
end

function ns.Toggle()
	if InCombatLockdown() then
		ns.Print("The teleprompter can't be shown or hidden in combat.")
		return
	end
	frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function Button(label, width, tooltip, onClick)
	local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(tooltip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

-- Scene navigation. Moves are broadcast to the whole group.
local function SceneBounds()
	local play, pos = ns.Play(), ns.State().pos
	local i = ns.SceneIndex(pos)
	local scene, nextScene = play.scenes[i], play.scenes[i + 1]
	local first = ns.NextActionable(scene.start)
	local last = (nextScene and nextScene.start or #play.cues + 1) - 1
	while last > first and not play.cues[last].r do
		last = last - 1
	end
	return i, first, last
end

local function GotoSceneStart()
	local i, first = SceneBounds()
	-- Already at the start: go to the start of the previous scene.
	if ns.State().pos <= first and i > 1 then
		ns.Goto(ns.Play().scenes[i - 1].start)
	else
		ns.Goto(first)
	end
end

local function GotoSceneEnd()
	local i, _, last = SceneBounds()
	local nextScene = ns.Play().scenes[i + 1]
	-- Already at the last cue: go on to the next scene.
	if ns.State().pos >= last and nextScene then
		ns.Goto(nextScene.start)
	else
		ns.Goto(last)
	end
end

local function StepBack()
	local cues = ns.Play().cues
	local i = math.min(ns.State().pos - 1, #cues)
	while i > 1 and not cues[i].r do
		i = i - 1
	end
	if i >= 1 and cues[i].r then ns.Goto(i) end
end

local function StepForward()
	local pos = ns.State().pos
	if pos <= #ns.Play().cues then ns.Goto(pos + 1) end
end

local function SecureButton(name, width)
	local b = CreateFrame("Button", name, frame, "SecureActionButtonTemplate,UIPanelButtonTemplate")
	b:SetSize(width, 26)
	if hasKeyDownCVar then
		b:RegisterForClicks("AnyUp", "AnyDown")
	else
		b:RegisterForClicks("AnyUp")
	end
	b:SetAttribute("type", "macro")
	b:SetAttribute("macrotext", "")
	return b
end

-- Drop-down list of the installed plays, opened from the title.
local function CreatePlayMenu()
	local ids = {}
	for id in pairs(ns.plays) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b) return ns.plays[a].title < ns.plays[b].title end)

	playMenu = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
	playMenu:SetBackdrop(ROW_BACKDROP)
	playMenu:SetBackdropColor(0, 0, 0, 0.95)
	playMenu:SetFrameStrata("DIALOG")
	playMenu:SetPoint("TOP", titleButton, "BOTTOM", 0, -2)
	playMenu:SetSize(300, 12 + #ids * 20)
	playMenu:Hide()

	local items = {}
	for i, id in ipairs(ids) do
		local item = CreateFrame("Button", nil, playMenu)
		item:SetSize(288, 20)
		item:SetPoint("TOP", 0, -6 - (i - 1) * 20)
		item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		item.text:SetPoint("CENTER")
		item:SetScript("OnClick", function()
			playMenu:Hide()
			if id ~= ns.State().playId then ns.ConfirmPlay(id) end
		end)
		items[id] = item
	end

	-- Mark the play currently being performed.
	playMenu:SetScript("OnShow", function()
		for id, item in pairs(items) do
			if id == ns.State().playId then
				item.text:SetText("|cffffd100" .. ns.plays[id].title .. "|r")
			else
				item.text:SetText(ns.plays[id].title)
			end
		end
	end)
end

function ns.CreateCastRow(i)
	local row = CreateFrame("Button", nil, castPanel)
	row:SetSize(castPanel:GetWidth() - 32, 16)
	row:SetPoint("TOPLEFT", 16, -32 - (i - 1) * 16)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", 2, 0)
	row.player = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.player:SetPoint("RIGHT", -2, 0)

	row:SetScript("OnClick", function(self)
		local id, holder = self.role.id, ns.State().cast[self.role.id]
		if holder == ns.Me() then
			ns.Uncast(id)
		elseif not holder or IsShiftKeyDown() then
			ns.Cast(id)
		else
			ns.Print(self.role.name .. " is played by " .. holder .. ". Shift-click to take the role.")
		end
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.role.name)
		if self.role.desc ~= "" then GameTooltip:AddLine(self.role.desc, 1, 1, 1, true) end
		GameTooltip:AddLine(self.role.cues .. " cues", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Click to take or give up the role.", 0.4, 0.8, 1, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)

	castRows[i] = row
	return row
end

function ns.CreateUI()
	frame = CreateFrame("Frame", "ShakespeareFrame", UIParent, BACKDROP_TEMPLATE)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetBackdrop(WINDOW_BACKDROP)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "ShakespeareFrame")  -- close with Escape

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	-- The title doubles as the play chooser.
	titleButton = CreateFrame("Button", nil, frame)
	titleButton:SetPoint("TOP", 0, -14)
	titleButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	frame.title = titleButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("CENTER")
	titleButton:SetScript("OnClick", function() playMenu:SetShown(not playMenu:IsShown()) end)
	titleButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Click to choose a play.", 1, 1, 1)
		GameTooltip:Show()
	end)
	titleButton:SetScript("OnLeave", GameTooltip_Hide)

	frame.scene = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.scene:SetPoint("TOP", titleButton, "BOTTOM", 0, -2)

	CreatePlayMenu()

	script = CreateFrame("Frame", nil, frame)
	script:SetPoint("TOPLEFT", 18, -60)
	script:SetPoint("BOTTOMRIGHT", -18, 74)
	script:SetClipsChildren(true)

	rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, script, BACKDROP_TEMPLATE)
		row:SetBackdrop(ROW_BACKDROP)
		row:SetPoint("LEFT")
		row:SetPoint("RIGHT")
		if i == 1 then
			row:SetPoint("TOP")
		else
			row:SetPoint("TOP", rows[i - 1], "BOTTOM", 0, -2)
		end
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("TOPLEFT", 8, -6)
		row.text:SetWidth(WIDTH - 52)
		row.text:SetJustifyH("LEFT")
		row.text:SetSpacing(2)
		rows[i] = row
	end

	-- Bottom bar: navigation, cast list, reset, prompt, deliver.
	local sceneStart = Button("<<", 32,
		"Start of the scene. Click again for the previous scene.", GotoSceneStart)
	sceneStart:SetPoint("BOTTOMLEFT", 18, 18)
	local back = Button("<", 28, "Back one line.", StepBack)
	back:SetPoint("LEFT", sceneStart, "RIGHT", 2, 0)
	local forward = Button(">", 28, "Skip one line.", StepForward)
	forward:SetPoint("LEFT", back, "RIGHT", 2, 0)
	local sceneEnd = Button(">>", 32,
		"End of the scene. Click again for the next scene.", GotoSceneEnd)
	sceneEnd:SetPoint("LEFT", forward, "RIGHT", 2, 0)

	local castButton = Button("Cast", 64, "Choose your roles.",
		function() castPanel:SetShown(not castPanel:IsShown()) end)
	castButton:SetPoint("LEFT", sceneEnd, "RIGHT", 8, 0)
	local resetButton = Button("Reset", 64,
		"Clear the cast and return to the start of the play, for everyone in the group.",
		function() ns.ConfirmReset() end)
	resetButton:SetPoint("LEFT", castButton, "RIGHT", 2, 0)

	local autoEmote = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	autoEmote:SetSize(24, 24)
	autoEmote:SetChecked(ns.State().autoEmote)
	autoEmote:SetScript("OnClick", function(self)
		ns.State().autoEmote = self:GetChecked() and true or false
		RefreshSecure()
	end)
	autoEmote:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Auto emotes")
		GameTooltip:AddLine("Speak also does the line's emote or spell. When off, use the Emote button.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	autoEmote:SetScript("OnLeave", GameTooltip_Hide)
	local autoLabel = autoEmote:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	autoLabel:SetPoint("LEFT", autoEmote, "RIGHT", 0, 1)
	autoLabel:SetText("Auto emotes")

	deliver = SecureButton("ShakespeareDeliverButton", 120)
	deliver:SetScript("PreClick", function(self, _, down)
		self.cueIndex = nil
		if not ClickIsLive(down) then return end
		local cue = ns.CurrentCue()
		if not ns.CanDeliver(cue) then return end
		self.cueIndex = ns.State().pos
		if cue.t then
			SendChatMessage((cue.t:gsub("\n", " ")), "SAY")
		end
	end)
	-- Advance only after the secure macro (emote or spell) for this cue has run.
	deliver:SetScript("PostClick", function(self, _, down)
		if ClickIsLive(down) and self.cueIndex then
			ns.Deliver(self.cueIndex)
		end
	end)

	-- Performs the emote or spell of the line just spoken (or about to be).
	emote = SecureButton("ShakespeareEmoteButton", 110)
	emote:SetText("Emote")
	emote:SetScript("OnEnter", function(self)
		local cue = ns.EmoteCue()
		if not cue then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(ActionLabel(cue))
		if cue.at then
			local player = ns.State().cast[cue.at]
			GameTooltip:AddLine("At " .. ns.RoleName(cue.at) .. (player and (" (" .. player .. ")") or " (not cast)"),
				1, 1, 1)
		end
		GameTooltip:Show()
	end)
	emote:SetScript("OnLeave", GameTooltip_Hide)

	prompt = SecureButton("ShakespearePromptButton", 110)

	-- Right-hand group, right to left: Emote, Speak, Prompt; the auto emotes
	-- checkbox sits above Emote.
	emote:SetPoint("BOTTOMRIGHT", -18, 17)
	deliver:SetPoint("RIGHT", emote, "LEFT", -6, 0)
	prompt:SetPoint("RIGHT", deliver, "LEFT", -6, 0)
	autoEmote:SetPoint("BOTTOMLEFT", emote, "TOPLEFT", 0, 2)
	prompt:SetScript("PostClick", function(_, _, down)
		if ClickIsLive(down) then
			ns.Prompted()
			RefreshSecure()
		end
	end)
	prompt:Hide()

	castPanel = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
	castPanel:SetWidth(240)
	castPanel:SetPoint("TOPLEFT", frame, "TOPRIGHT", -6, 0)
	castPanel:SetBackdrop(WINDOW_BACKDROP)
	castPanel:Hide()
	local castTitle = castPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	castTitle:SetPoint("TOP", 0, -16)
	castTitle:SetText("Dramatis Personae")

	-- The prompt button appears after a delay, so poll while visible.
	C_Timer.NewTicker(0.5, function()
		if frame:IsShown() then RefreshSecure() end
	end)

	ns.Refresh()
end
