MAGNIFY_MIN_ZOOM = 1.0
MAGNIFY_MAX_ZOOM = 1.6
MAGNIFY_ZOOM_STEP = 0.2
MAGNIFY_PLAYER_FLASH_INTERVAL = 0.25
MAGNIFY_PLAYER_FLASH_COUNT = 10

-- native size of the stock map and its tiles; zoom is applied by resizing, never by scaling,
-- so every addon that positions pins from WorldMapButton/WorldMapDetailFrame width/height stays correct
local MAP_WIDTH, MAP_HEIGHT, TILE_SIZE = 1002, 668, 256

local zoom = 1
local nextClip = 0

-- map fade while the player moves
local FADE_SPEED = 3 -- alpha units per second
local MOVE_EPSILON = 0.05 -- yards per check that count as moving
local MOVE_INTERVAL = 0.1
local MOVE_HOLD = 0.3
local fadeX, fadeY

-- the map never takes the mouse itself: clicks and the wheel go to the camera, and a quick click on the
-- map is picked up from WorldFrame instead
local CLICK_MAX_TIME = 0.25
local MOUSE_INTERVAL = 0.1
local nextMouseCheck = 0
local bothHeld, bothSeen = false, false
local downTime = {}
local fadeLastMove = 0
local nextMoveCheck = 0

-- upvalues
local abs = math.abs
local floor = math.floor
local min, max = math.min, math.max

local GetCursorPosition = GetCursorPosition
local GetPlayerMapPosition = GetPlayerMapPosition
local GetPlayerFacing = GetPlayerFacing

-- pins parented outside the scroll child (e.g. Questie's) are not clipped by the scroll frame, so
-- while zoomed in, fade out and disable the ones that are not fully inside the viewport
local function ClipPins()
	local viewport = WorldMapFrameScrollFrame
	local zoomed = viewport.zoomedIn
	local left, right, top, bottom

	if zoomed then
		local scale = viewport:GetEffectiveScale()

		left, right = viewport:GetLeft() * scale, viewport:GetRight() * scale
		top, bottom = viewport:GetTop() * scale, viewport:GetBottom() * scale
	end

	local pins = { WorldMapFrame:GetChildren() }
	for _, pin in ipairs({ WorldMapButton:GetChildren() }) do
		table.insert(pins, pin)
	end

	for _, pin in ipairs(pins) do
		local _, relativeTo = pin:GetPoint()

		if relativeTo == WorldMapButton or relativeTo == WorldMapDetailFrame then
			local inside = true

			if zoomed then
				local pinScale = pin:GetEffectiveScale()
				local pinLeft = pin:GetLeft()

				inside = not pinLeft or (pinLeft * pinScale >= left and pin:GetRight() * pinScale <= right
					and pin:GetTop() * pinScale <= top and pin:GetBottom() * pinScale >= bottom)
			end

			if inside then
				if pin.magnifyClipped then
					pin.magnifyClipped = nil
					pin:EnableMouse(pin.magnifyMouse)

					if pin:GetAlpha() == 0 then
						pin:SetAlpha(pin.magnifyAlpha)
					end
				end
			else
				if not pin.magnifyClipped then
					pin.magnifyClipped = true
					pin.magnifyMouse = pin:IsMouseEnabled()
				end

				-- addons reset a pin's alpha when they redraw it, so hide it again every pass
				if pin:GetAlpha() > 0 then
					pin.magnifyAlpha = pin:GetAlpha()
					pin:SetAlpha(0)
				end

				pin:EnableMouse(false)
			end
		end
	end
end

local function ScrollTo(x, y)
	local frame = WorldMapFrameScrollFrame

	x = max(0, min(x, WorldMapDetailFrame:GetWidth() - frame:GetWidth()))
	y = max(0, min(y, WorldMapDetailFrame:GetHeight() - frame:GetHeight()))

	frame:SetHorizontalScroll(-x)
	frame:SetVerticalScroll(y)

	ClipPins()
end

-- the map itself is click-through, so a windowed map (DMV, ShaguTweaks, pfUI) is moved by its title bar. The map art
-- is a fixed 1024x768 picture centred on the map frame, which is what WorldMapPositioningGuide matches: in a smaller
-- window the bar sticks out above the frame's own rectangle. The handle is a child of the map, so it follows its scale.
local dragHandle = CreateFrame('Frame', 'MagnifyDragHandle', WorldMapFrame)
dragHandle:SetHeight(26)
dragHandle:SetPoint('TOPLEFT', WorldMapPositioningGuide, 'TOPLEFT')
dragHandle:SetPoint('TOPRIGHT', WorldMapPositioningGuide, 'TOPRIGHT')
-- level of the map itself, so the title bar's buttons and dropdowns stay on top
dragHandle:SetFrameLevel(WorldMapFrame:GetFrameLevel())
dragHandle:RegisterForDrag('LeftButton')
dragHandle:SetScript('OnDragStart', function()
	WorldMapFrame:SetMovable(true)
	WorldMapFrame:StartMoving()
end)
dragHandle:SetScript('OnDragStop', function() WorldMapFrame:StopMovingOrSizing() end)

-- DungeonMapsVanilla draws its own map over the world map; it takes the left button and the wheel itself
local function ExternalMapUp()
	return DMV_ClickFrame and DMV_ClickFrame:IsShown()
end

local function ApplyClickThrough()
	local viewport = WorldMapFrameScrollFrame

	WorldMapFrame:EnableMouse(false)
	WorldMapButton:EnableMouse(false)

	-- the stock map takes the keyboard, which swallows every binding (side mouse buttons included); the toggle
	-- key and Escape still close it through the game's own bindings
	WorldMapFrame:EnableKeyboard(false)

	-- a fullscreen map has nowhere to go, so its title bar stays click-through
	dragHandle:EnableMouse(WorldMapFrame:GetWidth() * WorldMapFrame:GetEffectiveScale() < UIParent:GetWidth() * UIParent:GetEffectiveScale() - 1)

	-- the scroll frame keeps the wheel for zooming. A frame that takes the wheel swallows every click on it, so
	-- its buttons are passed through to the camera instead; zoomed in, the left button is kept to drag the map
	if ExternalMapUp() then
		viewport:EnableMouse(false)
		viewport:EnableMouseWheel(false)

		-- its right button turns the camera; a quick click is passed on to it from WorldFrame
		DMV_ClickFrame:SetPassThroughButtons('RightButton', 'MiddleButton', 'Button4', 'Button5')
	else
		viewport:EnableMouse(true)
		viewport:EnableMouseWheel(true)

		if viewport.zoomedIn then
			viewport:SetPassThroughButtons('RightButton', 'MiddleButton', 'Button4', 'Button5')
		else
			viewport:SetPassThroughButtons('LeftButton', 'RightButton', 'MiddleButton', 'Button4', 'Button5')
		end
	end
end

-- while another addon's map is up, the world map underneath is invisible and ignores the mouse
local baseHidden = false

local function SetBaseMapHidden(hide)
	local alpha = hide and 0 or 1

	baseHidden = hide

	for i = 1, NUM_WORLDMAP_DETAIL_TILES do
		getglobal('WorldMapDetailTile' .. i):SetAlpha(alpha)
	end

	for i = 1, NUM_WORLDMAP_OVERLAYS do
		getglobal('WorldMapOverlay' .. i):SetAlpha(alpha)
	end

	for i = 1, NUM_WORLDMAP_POIS do
		local poi = getglobal('WorldMapFramePOI' .. i)

		poi:SetAlpha(alpha)
		poi:EnableMouse(not hide)
	end

	for i = 1, MAX_RAID_MEMBERS do
		local raid = getglobal('WorldMapRaid' .. i)

		raid:SetAlpha(alpha)
		raid:EnableMouse(not hide)
	end

	for i = 1, MAX_PARTY_MEMBERS do
		local party = getglobal('WorldMapParty' .. i)

		party:SetAlpha(alpha)
		party:EnableMouse(not hide)
	end

	WorldMapHighlight:SetAlpha(alpha)
	WorldMapFrameAreaFrame:SetAlpha(alpha)
end

local function RescalePoint(object, ratio)
	local point, relativeTo, relativePoint, x, y = object:GetPoint()

	if relativeTo == WorldMapButton or relativeTo == WorldMapDetailFrame then
		object:SetPoint(point, relativeTo, relativePoint, x * ratio, y * ratio)
	end
end

-- addons place their pins once, as pixel offsets from the map corner: carry them to the new size
local function RescalePins(frame, ratio)
	for _, region in ipairs({ frame:GetRegions() }) do
		RescalePoint(region, ratio)
	end

	for _, child in ipairs({ frame:GetChildren() }) do
		RescalePoint(child, ratio)
		RescalePins(child, ratio)
	end
end

local function SetZoom(newZoom)
	RescalePins(WorldMapFrame, newZoom / zoom)

	zoom = newZoom

	local width, height, tileSize = MAP_WIDTH * zoom, MAP_HEIGHT * zoom, TILE_SIZE * zoom

	WorldMapDetailFrame:SetWidth(width)
	WorldMapDetailFrame:SetHeight(height)
	WorldMapButton:SetWidth(width)
	WorldMapButton:SetHeight(height)

	for i = 1, NUM_WORLDMAP_DETAIL_TILES do
		local tile = getglobal('WorldMapDetailTile' .. i)
		tile:SetWidth(tileSize)
		tile:SetHeight(tileSize)
	end

	WorldMapFrameScrollFrame:UpdateScrollChildRect()

	-- re-lays out POIs from the new button size and re-applies the overlays
	WorldMapFrame_Update()
end

-- the stock update sizes overlays in native pixels, scale them to the current zoom
hooksecurefunc('WorldMapFrame_Update', function()
	for i = 1, NUM_WORLDMAP_OVERLAYS do
		local overlay = getglobal('WorldMapOverlay' .. i)
		if not overlay:IsShown() then
			break
		end

		local _, _, _, x, y = overlay:GetPoint()

		overlay:SetWidth(overlay:GetWidth() * zoom)
		overlay:SetHeight(overlay:GetHeight() * zoom)
		overlay:SetPoint('TOPLEFT', 'WorldMapDetailFrame', 'TOPLEFT', x * zoom, y * zoom)
	end
end)

function WorldMapFrameScrollFrame_OnMouseDown()
	if arg1 == 'LeftButton' and this.zoomedIn then
		this.panning = true

		this.cursorX, this.cursorY = GetCursorPosition()
		this.x = -this:GetHorizontalScroll()
		this.y = this:GetVerticalScroll()
		this.moved = false
	end
end

function WorldMapFrameScrollFrame_OnMouseUp()
	this.panning = false

	if not this.moved then
		WorldMapButton_OnClick(arg1, WorldMapButton)

		Magnify_ResetZoom()
	end

	this.moved = false
end

function WorldMapFrameScrollFrame_OnMouseWheel()
	local scale = this:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()

	local frameX = cursorX / scale - this:GetLeft()
	local frameY = this:GetTop() - cursorY / scale

	local newZoom = floor((zoom + arg1 * MAGNIFY_ZOOM_STEP) * 1000 + 0.5) / 1000
	newZoom = max(MAGNIFY_MIN_ZOOM, min(MAGNIFY_MAX_ZOOM, newZoom))

	if newZoom == zoom then
		return
	end

	-- map point under the cursor, as a fraction of the map
	local mapX = (-this:GetHorizontalScroll() + frameX) / WorldMapDetailFrame:GetWidth()
	local mapY = (this:GetVerticalScroll() + frameY) / WorldMapDetailFrame:GetHeight()

	SetZoom(newZoom)

	this.zoomedIn = newZoom > MAGNIFY_MIN_ZOOM

	ApplyClickThrough()
	ScrollTo(mapX * WorldMapDetailFrame:GetWidth() - frameX, mapY * WorldMapDetailFrame:GetHeight() - frameY)
end

local function WorldMapFrameScrollFrame_OnPan(cursorX, cursorY)
	local frame = WorldMapFrameScrollFrame
	local scale = frame:GetEffectiveScale()

	local dX = (frame.cursorX - cursorX) / scale
	local dY = (cursorY - frame.cursorY) / scale

	if abs(dX) >= 1 or abs(dY) >= 1 then
		frame.moved = true

		ScrollTo(frame.x + dX, frame.y + dY)
	end
end

local function PlayerMoved()
	local y, x = UnitPosition('player')
	if not y then
		return false
	end

	local moved = fadeX and (x - fadeX) * (x - fadeX) + (y - fadeY) * (y - fadeY) > MOVE_EPSILON * MOVE_EPSILON

	fadeX, fadeY = x, y

	return moved
end

local function UpdateFade(elapsed)
	local now = GetTime()
	local enabled = Magnify_Settings['fade'] ~= false and not UnitOnTaxi('player')

	if now >= nextMoveCheck then
		nextMoveCheck = now + MOVE_INTERVAL

		if not enabled then
			fadeX = nil
			fadeLastMove = 0
		elseif PlayerMoved() then
			fadeLastMove = now
		end
	end

	local target = 1
	if enabled and now - fadeLastMove < MOVE_HOLD then
		target = Magnify_Settings['fade_alpha'] or 0.35
	end

	local alpha = WorldMapFrame:GetAlpha()
	local step = FADE_SPEED * elapsed

	if alpha > target then
		WorldMapFrame:SetAlpha(max(target, alpha - step))
	elseif alpha < target then
		WorldMapFrame:SetAlpha(min(target, alpha + step))
	end
end

local function OtherButton(button)
	return button == 'LeftButton' and 'RightButton' or 'LeftButton'
end

-- the viewport as well as the button: zoomed in, the button extends past the window
local function CursorOverMap()
	return WorldMapFrame:IsVisible() and MouseIsOver(WorldMapButton) and MouseIsOver(WorldMapFrameScrollFrame)
end

local function WorldFrame_OnMouseDown(self, button)
	downTime[button] = GetTime()

	if IsMouseButtonDown(OtherButton(button)) then
		bothSeen = true
	end
end

local function WorldFrame_OnMouseUp(self, button)
	local other = OtherButton(button)
	local pressed = downTime[button]

	downTime[button] = nil

	-- mouse-walking (both buttons) must never count as a map click
	local walking = bothSeen or bothHeld or IsMouseButtonDown(other)

	if not IsMouseButtonDown(other) and not downTime[other] then
		bothSeen = false
	end

	if walking or not pressed or GetTime() - pressed > CLICK_MAX_TIME or not CursorOverMap() then
		return
	end

	if not ExternalMapUp() then
		WorldMapButton_OnClick(button, WorldMapButton)
	elseif button == 'RightButton' then
		-- DMV's own right click: back / zoom out
		local handler = DMV_ClickFrame:GetScript('OnMouseDown')
		local oldThis, oldArg1 = this, arg1

		this, arg1 = DMV_ClickFrame, button
		handler(DMV_ClickFrame, button)
		this, arg1 = oldThis, oldArg1
	end
end

local function UpdateMouse()
	local left, right = IsMouseButtonDown('LeftButton'), IsMouseButtonDown('RightButton')

	if left and right then
		bothHeld = true
	elseif not left and not right then
		bothHeld = false
	end

	if GetTime() >= nextMouseCheck then
		nextMouseCheck = GetTime() + MOUSE_INTERVAL

		ApplyClickThrough()

		-- re-applied while hidden: addons redraw their pins and highlights
		local hide = ExternalMapUp() and true or false

		-- the other addon's map does not follow Magnify's zoom, so start it zoomed out
		if hide and not baseHidden then
			Magnify_ResetZoom()
		end

		if hide or baseHidden then
			SetBaseMapHidden(hide)
		end
	end
end

local function WorldMapButton_OnUpdate()
	UpdateFade(arg1)
	UpdateMouse()

	if WorldMapFrameScrollFrame.panning then
		WorldMapFrameScrollFrame_OnPan(GetCursorPosition())
	end

	-- catch pins an addon (re)placed since the last scroll
	if WorldMapFrameScrollFrame.zoomedIn and GetTime() > nextClip then
		nextClip = GetTime() + 0.2

		ClipPins()
	end

	local x, y = GetPlayerMapPosition('player')

	if x == 0 and y == 0 then
		WorldMapPlayer.Icon:Hide()
	else
		WorldMapPlayer.Icon:Show()
		WorldMapPlayer.Icon:SetRotation(GetPlayerFacing())
	end
end

local function WorldMapPlayer_OnUpdate()
	this.Elapsed = this.Elapsed + arg1

	if this.Elapsed > MAGNIFY_PLAYER_FLASH_INTERVAL then
		this.Elapsed = 0

		if this.Flashes < MAGNIFY_PLAYER_FLASH_COUNT then
			this.Flashes = this.Flashes + 1

			if this:GetAlpha() == 1 then
				this:SetAlpha(0)
			else
				this:SetAlpha(1)
			end
		else
			this.Flashes = 0
			this:SetAlpha(1)
			this:SetScript('OnUpdate', nil)
		end
	end
end

local function WorldMapFrame_OnShow()
	ApplyClickThrough()

	if Magnify_Settings['arrow_flash'] then
		WorldMapPlayer:SetScript('OnUpdate', WorldMapPlayer_OnUpdate)
	else
		WorldMapPlayer:SetAlpha(1)
	end
end

local function WorldMapFrame_OnHide()
	WorldMapFrameScrollFrame.panning = false

	if baseHidden then
		SetBaseMapHidden(false)
	end

	-- start the next open fully opaque and without a stale movement reading
	WorldMapFrame:SetAlpha(1)
	fadeX = nil
	fadeLastMove = 0
	nextMoveCheck = 0

	WorldMapPlayer.Flashes = 0
	WorldMapPlayer:SetScript('OnUpdate', nil)

	if Magnify_Settings['zoom_reset'] then
		Magnify_ResetZoom()
	end
end

local function HandleEvent()
	if not Magnify_Settings then
		Magnify_Settings = {
			['arrow_flash'] = true,
			['arrow_scale'] = 1,
			['max_zoom'] = 1.6,
			['zoom_reset'] = false
		}
	end

	MAGNIFY_MAX_ZOOM = (Magnify_Settings['max_zoom'] or MAGNIFY_MAX_ZOOM)

	Magnify_HookWindow()

	if WORLDMAP_WINDOWED then
		if WORLDMAP_WINDOWED == 1 then
			WorldMapFrame_Minimize()
		else
			WorldMapFrame_Maximize()
		end
	end

	-- adjust map zone text position
	WorldMapFrameAreaFrame:SetParent(WorldMapFrame)
	WorldMapFrameAreaFrame:ClearAllPoints()
	WorldMapFrameAreaFrame:SetPoint('TOP', WorldMapFrame, 0, -60)
	WorldMapFrameAreaFrame:SetFrameStrata('FULLSCREEN_DIALOG')

	WorldMapButton:SetParent(WorldMapDetailFrame)
	WorldMapButton:SetFrameLevel(0)

	-- hide player indicator and ping model
	-- credit: https://github.com/Road-block/Cartographer
	local children = { WorldMapFrame:GetChildren() }
	for _, v in ipairs(children) do
		if v:GetFrameType() == 'Model' and not v:GetName() then
			v:SetScript('OnShow', function() this:Hide() end)

			break
		end
	end

	WorldMapPing.Show = function() return end
	WorldMapPing:SetModelScale(0)

	-- replace player indicator model with a better solution
	local size = 24 * (Magnify_Settings['arrow_scale'] or 1)

	WorldMapPlayer.Icon = WorldMapPlayer:CreateTexture('WorldMapPlayerIcon', 'ARTWORK')
	WorldMapPlayer.Icon:SetWidth(size)
	WorldMapPlayer.Icon:SetHeight(size)
	WorldMapPlayer.Icon:SetPoint('CENTER', WorldMapPlayer)
	WorldMapPlayer.Icon:SetTexture('Interface\\AddOns\\Magnify\\assets\\WorldMapArrow')
	
	WorldMapPlayer.Flashes = 0
	WorldMapPlayer.Elapsed = 0

	-- extend the stock scripts
	WorldMapButton:HookScript('OnUpdate', WorldMapButton_OnUpdate)

	WorldMapFrame:HookScript('OnShow', WorldMapFrame_OnShow)
	WorldMapFrame:HookScript('OnHide', WorldMapFrame_OnHide)

	-- an intrinsic hook survives other addons calling SetScript on WorldFrame
	WorldFrame:HookScript('OnMouseDown', WorldFrame_OnMouseDown, LE_SCRIPT_BINDING_TYPE_INTRINSIC_POSTCALL)
	WorldFrame:HookScript('OnMouseUp', WorldFrame_OnMouseUp, LE_SCRIPT_BINDING_TYPE_INTRINSIC_POSTCALL)
end

local handler = CreateFrame('Frame')
handler:RegisterEvent('VARIABLES_LOADED')
handler:SetScript('OnEvent', HandleEvent)

function Magnify_ResetZoom()
	SetZoom(MAGNIFY_MIN_ZOOM)

	WorldMapFrameScrollFrame.zoomedIn = false

	ApplyClickThrough()
	ScrollTo(0, 0)
end
