-- Minimap button: click to show the teleprompter, drag to move it around the minimap.
local _, ns = ...

local ICON = "Interface\\AddOns\\Shakespeare\\media\\harp"
local RADIUS_PADDING = 5
local DEFAULT_ANGLE = 200

local button

local function UpdatePosition()
	local angle = math.rad(ns.State().minimapAngle or DEFAULT_ANGLE)
	local r = Minimap:GetWidth() / 2 + RADIUS_PADDING
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	ns.State().minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	UpdatePosition()
end

function ns.CreateMinimapButton()
	button = CreateFrame("Button", "ShakespeareMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER", background, "CENTER")

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			ns.ConfirmReset()
		else
			ns.Toggle()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Shakespeare")
		local play = ns.Play()
		if play then GameTooltip:AddLine(play.title, 1, 1, 1) end
		GameTooltip:AddLine("Click to show or hide the teleprompter.", 0.4, 0.8, 1)
		GameTooltip:AddLine("Right-click to reset.", 0.4, 0.8, 1)
		GameTooltip:AddLine("Drag to move this button.", 0.4, 0.8, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	UpdatePosition()
end
