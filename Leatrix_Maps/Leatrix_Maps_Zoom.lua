
	----------------------------------------------------------------------
	-- Leatrix Maps Zoom
	-- Map zoom and pan feature, adapted from Magnify-WotLK
	----------------------------------------------------------------------

	local ADDON_NAME, _ = ...
	LeaMapsZoom = {}

	----------------------------------------------------------------------
	-- Constants
	----------------------------------------------------------------------

	LeaMapsZoom.MIN_ZOOM = 1.0

	LeaMapsZoom.MINIMODE_MIN_ZOOM = 1.0
	LeaMapsZoom.MINIMODE_MAX_ZOOM = 3.0
	LeaMapsZoom.MINIMODE_ZOOM_STEP = 0.1

	LeaMapsZoom.WORLDMAP_POI_MIN_X = 12
	LeaMapsZoom.WORLDMAP_POI_MIN_Y = -12
	LeaMapsZoom.worldmapPoiMaxX = nil
	LeaMapsZoom.worldmapPoiMaxY = nil

	LeaMapsZoom.PLAYER_ARROW_SIZE = 36

	-- Ascension's client composites the objective blob glow AFTER the whole
	-- UI renders, so it can never be layered below the quest POI buttons
	-- (verified: even TOOLTIP-strata buttons draw under it). The fill is
	-- the glow's body but also the wash that tints the numbered icon, so
	-- this is a balance dial: higher = fuller glow but more tint on the
	-- number, lower = crisper number but thinner glow.
	-- Stock values: fill 128, border 192.
	LeaMapsZoom.BLOB_FILL_ALPHA   = 64
	LeaMapsZoom.BLOB_BORDER_ALPHA = 192

	LeaMapsZoom.ENABLEPERSISTZOOM_DEFAULT  = false
	LeaMapsZoom.ENABLEOLDPARTYICONS_DEFAULT = false
	LeaMapsZoom.MAXZOOM_DEFAULT            = 4.0
	LeaMapsZoom.MAXZOOM_SLIDER_MIN         = 2.0
	LeaMapsZoom.MAXZOOM_SLIDER_MAX         = 10.0
	LeaMapsZoom.MAXZOOM_SLIDER_STEP        = 0.5
	LeaMapsZoom.ZOOMSTEP_DEFAULT           = 0.1
	LeaMapsZoom.ZOOMSTEP_SLIDER_MIN        = 0.01
	LeaMapsZoom.ZOOMSTEP_SLIDER_MAX        = 0.5
	LeaMapsZoom.ZOOMSTEP_SLIDER_STEP       = 0.01

	-- Previous state for persist-zoom feature
	LeaMapsZoom.PreviousState = {
		panX  = 0,
		panY  = 0,
		scale = 1,
		zone  = 0,
	}

	-- Saved options (persisted via SavedVariables in the TOC)
	MagnifyOptions = {
		enablePersistZoom   = false,
		enableOldPartyIcons = false,
		maxZoom             = LeaMapsZoom.MAXZOOM_DEFAULT,
		zoomStep            = LeaMapsZoom.ZOOMSTEP_DEFAULT,
	}

	----------------------------------------------------------------------
	-- Local utilities
	----------------------------------------------------------------------

	local function updatePointRelativeTo(frame, newRelativeFrame)
		local currentPoint, _f, currentRelativePoint, currentOffsetX, currentOffsetY = frame:GetPoint()
		frame:ClearAllPoints()
		frame:SetPoint(currentPoint, newRelativeFrame, currentRelativePoint, currentOffsetX, currentOffsetY)
	end

	local function resizePOI(poiButton)
		if poiButton then
			-- Keep quest POI buttons above the objective blob frame (the
			-- glow itself is composited over the UI by Ascension's client
			-- and cannot be out-layered; see BLOB_FILL_ALPHA above)
			if WorldMapBlobFrame and poiButton:GetFrameLevel() <= WorldMapBlobFrame:GetFrameLevel() then
				poiButton:SetFrameLevel(WorldMapBlobFrame:GetFrameLevel() + 2)
			end
			local _, _, _, x, y = poiButton:GetPoint()
			if x ~= nil and y ~= nil then
				local s = WORLDMAP_SETTINGS.size / WorldMapDetailFrame:GetEffectiveScale()
				local posX = x * 1 / s
				local posY = y * 1 / s
				poiButton:SetScale(s)
				poiButton:SetPoint("CENTER", poiButton:GetParent(), "TOPLEFT", posX, posY)
				if posY > LeaMapsZoom.WORLDMAP_POI_MIN_Y then
					posY = LeaMapsZoom.WORLDMAP_POI_MIN_Y
				elseif LeaMapsZoom.worldmapPoiMaxY and posY < LeaMapsZoom.worldmapPoiMaxY then
					posY = LeaMapsZoom.worldmapPoiMaxY
				end
				if posX < LeaMapsZoom.WORLDMAP_POI_MIN_X then
					posX = LeaMapsZoom.WORLDMAP_POI_MIN_X
				elseif LeaMapsZoom.worldmapPoiMaxX and posX > LeaMapsZoom.worldmapPoiMaxX then
					posX = LeaMapsZoom.worldmapPoiMaxX
				end
			end
		end
	end

	local function isFrameOnWorldMap(frame)
		local current = frame
		while current do
			if current == WorldMapFrame or current == WorldMapScrollFrame or
			   current == WorldMapDetailFrame or current == WorldMapButton or
			   current == WorldMapPOIFrame then
				return true
			end
			if not current.GetParent then break end
			local nextParent = current:GetParent()
			if nextParent == current then break end
			current = nextParent
		end
		return false
	end

	local function isCloseEnough(a, b, epsilon)
		return math.abs((a or 0) - (b or 0)) <= (epsilon or 0.01)
	end

	local function isCornerPoint(point)
		return point == "TOPLEFT" or point == "TOPRIGHT" or
		       point == "BOTTOMLEFT" or point == "BOTTOMRIGHT"
	end

	local function isQuestieMapCornerButton(frameObject, point, relativeFrame, relativePoint, offsetX, offsetY)
		if frameObject.__magnifyQuestieCornerLocked then return true end
		if relativeFrame ~= WorldMapButton then return false end
		if not isCornerPoint(point) or not isCornerPoint(relativePoint) then return false end
		if type(offsetX) ~= "number" or type(offsetY) ~= "number" then return false end
		return math.abs(offsetX) <= 40 and math.abs(offsetY) <= 40
	end

	local function lockQuestieMapCornerButton(frameObject, point, relativePoint, offsetX, offsetY, detailFrameScale)
		if isCloseEnough(detailFrameScale, 1, 0.02) then
			frameObject.__magnifyQuestieCornerBaseX = offsetX
			frameObject.__magnifyQuestieCornerBaseY = offsetY
		elseif not frameObject.__magnifyQuestieCornerBaseX or not frameObject.__magnifyQuestieCornerBaseY then
			frameObject.__magnifyQuestieCornerBaseX = offsetX
			frameObject.__magnifyQuestieCornerBaseY = offsetY
		end
		frameObject.__magnifyQuestieCornerPoint         = frameObject.__magnifyQuestieCornerPoint or point
		frameObject.__magnifyQuestieCornerRelativePoint = frameObject.__magnifyQuestieCornerRelativePoint or relativePoint
		frameObject.__magnifyQuestieCornerLocked        = true

		local lockPoint         = frameObject.__magnifyQuestieCornerPoint or point
		local lockRelativePoint = frameObject.__magnifyQuestieCornerRelativePoint or relativePoint
		local lockX             = frameObject.__magnifyQuestieCornerBaseX or offsetX
		local lockY             = frameObject.__magnifyQuestieCornerBaseY or offsetY
		local _, currentRelativeFrame, currentRelativePoint, currentX, currentY = frameObject:GetPoint(1)

		if frameObject:GetParent() ~= WorldMapScrollFrame or
		   currentRelativeFrame ~= WorldMapScrollFrame or
		   currentRelativePoint ~= lockRelativePoint or
		   not isCloseEnough(currentX, lockX, 0.05) or
		   not isCloseEnough(currentY, lockY, 0.05) then
			frameObject:SetParent(WorldMapScrollFrame)
			frameObject:ClearAllPoints()
			frameObject:SetPoint(lockPoint, WorldMapScrollFrame, lockRelativePoint, lockX, lockY)
		end
		frameObject:SetScale(1)
	end

	local function getAnchorPointCoordinates(point, width, height)
		if point == "TOPLEFT"     then return 0,           0
		elseif point == "TOP"     then return width / 2,   0
		elseif point == "TOPRIGHT" then return width,      0
		elseif point == "LEFT"    then return 0,           -height / 2
		elseif point == "CENTER"  then return width / 2,   -height / 2
		elseif point == "RIGHT"   then return width,       -height / 2
		elseif point == "BOTTOMLEFT"  then return 0,       -height
		elseif point == "BOTTOM"  then return width / 2,   -height
		elseif point == "BOTTOMRIGHT" then return width,   -height
		end
		return 0, 0
	end

	local function clamp(number, minValue, maxValue)
		if number < minValue then return minValue
		elseif number > maxValue then return maxValue
		end
		return number
	end

	local function getQuestieVisibleBounds(anchorFrame)
		local left   = 0
		local right  = anchorFrame:GetWidth() or 0
		local top    = 0
		local bottom = -(anchorFrame:GetHeight() or 0)

		if anchorFrame == WorldMapButton or anchorFrame == WorldMapDetailFrame then
			local detailFrameScale = WorldMapDetailFrame:GetScale()
			if detailFrameScale and detailFrameScale > 0 then
				local scrollLeft    = WorldMapScrollFrame:GetHorizontalScroll() or 0
				local scrollTop     = WorldMapScrollFrame:GetVerticalScroll() or 0
				local visibleWidth  = WorldMapScrollFrame:GetWidth() or 0
				local visibleHeight = WorldMapScrollFrame:GetHeight() or 0
				left   = scrollLeft * detailFrameScale
				right  = left + visibleWidth
				top    = -(scrollTop * detailFrameScale)
				bottom = top - visibleHeight
			end
		end
		return left, right, bottom, top
	end

	local function clampQuestieMapPinOffset(frameObject, anchorFrame, point, relativePoint, offsetX, offsetY)
		if not frameObject or not anchorFrame or not point or not relativePoint then
			return offsetX, offsetY
		end
		if not anchorFrame.GetWidth or not anchorFrame.GetHeight or
		   not frameObject.GetWidth or not frameObject.GetHeight then
			return offsetX, offsetY
		end
		local anchorWidth  = anchorFrame:GetWidth() or 0
		local anchorHeight = anchorFrame:GetHeight() or 0
		if anchorWidth <= 0 or anchorHeight <= 0 then return offsetX, offsetY end

		local frameWidth  = frameObject:GetWidth() or 0
		local frameHeight = frameObject:GetHeight() or 0
		local relativePointX, relativePointY = getAnchorPointCoordinates(relativePoint, anchorWidth, anchorHeight)
		local pointX, pointY = getAnchorPointCoordinates(point, frameWidth, frameHeight)
		local absoluteX = relativePointX + offsetX
		local absoluteY = relativePointY + offsetY

		local left, right, bottom, top = getQuestieVisibleBounds(anchorFrame)
		local minX = left + pointX
		local maxX = right - (frameWidth - pointX)
		if maxX < minX then minX = (left + right) / 2; maxX = minX end
		local minY = bottom + frameHeight + pointY
		local maxY = top + pointY
		if maxY < minY then minY = (bottom + top) / 2; maxY = minY end

		local clampedX = clamp(absoluteX, minX, maxX)
		local clampedY = clamp(absoluteY, minY, maxY)
		return clampedX - relativePointX, clampedY - relativePointY
	end

	----------------------------------------------------------------------
	-- Questie pin management
	----------------------------------------------------------------------

	-- Disabled: Questie pins are now managed by Questie itself
	function LeaMapsZoom.SetQuestieWorldMapPinsVisible(isVisible)
		-- Intentionally empty: Questie manages its own pins
	end

	-- Disabled: Questie pins are now managed by Questie itself
	function LeaMapsZoom.SyncQuestieWorldMapPins(forceRescan)
		-- Intentionally empty: Questie manages its own pins, we don't touch them
	end

	----------------------------------------------------------------------
	-- Scroll / pan helpers
	----------------------------------------------------------------------

	function LeaMapsZoom.PersistMapScrollAndPan()
		LeaMapsZoom.PreviousState.panX  = WorldMapScrollFrame:GetHorizontalScroll()
		LeaMapsZoom.PreviousState.panY  = WorldMapScrollFrame:GetVerticalScroll()
		LeaMapsZoom.PreviousState.scale = WorldMapDetailFrame:GetScale()
		LeaMapsZoom.PreviousState.zone  = GetCurrentMapZone()
	end

	-- WorldMapBlobFrame (quest objective glow) renders in screen space and
	-- only repaints on a DrawQuestBlob call, so it must be repainted after
	-- any move, pan or scale of the map
	function LeaMapsZoom.RepaintBlob()
		if WORLDMAP_SETTINGS.selectedQuest then
			WorldMapBlobFrame:DrawQuestBlob(WORLDMAP_SETTINGS.selectedQuestId, false)
			WorldMapBlobFrame:DrawQuestBlob(WORLDMAP_SETTINGS.selectedQuestId, true)
		end
		WorldMapBlobFrame:SetFillAlpha(LeaMapsZoom.BLOB_FILL_ALPHA)
		WorldMapBlobFrame:SetBorderAlpha(LeaMapsZoom.BLOB_BORDER_ALPHA)
	end

	function LeaMapsZoom.AfterScrollOrPan()
		LeaMapsZoom.PersistMapScrollAndPan()
		LeaMapsZoom.RepaintBlob()
	end

	-- Hide the blob while the map window is dragged or scaled (it would
	-- stay behind at its old screen position) and repaint it afterwards
	function LeaMapsZoom.BeginWindowDrag()
		if WorldMapBlobFrame:IsShown() then
			LeaMapsZoom.blobWasShown = true
			WorldMapBlobFrame:Hide()
		end
	end

	function LeaMapsZoom.EndWindowDrag()
		if LeaMapsZoom.blobWasShown then
			LeaMapsZoom.blobWasShown = nil
			WorldMapBlobFrame:Show()
		end
		LeaMapsZoom.RepaintBlob()
	end

	function LeaMapsZoom.ResizeQuestPOIs()
		-- Bounds are set by SetPOIMaxBounds (called from SetDetailFrameScale).
		-- If the map hasn't been set up yet the first time, skip to avoid nil compare.
		if not LeaMapsZoom.worldmapPoiMaxY then return end
		local QUEST_POI_MAX_TYPES  = 4
		local POI_TYPE_MAX_BUTTONS = 25
		for i = 1, QUEST_POI_MAX_TYPES do
			for j = 1, POI_TYPE_MAX_BUTTONS do
				resizePOI(_G["poiWorldMapPOIFrame" .. i .. "_" .. j])
			end
		end
		if QUEST_POI_SWAP_BUTTONS then
			resizePOI(QUEST_POI_SWAP_BUTTONS["WorldMapPOIFrame"])
		end
		LeaMapsZoom._resizedAtScale = WorldMapDetailFrame:GetEffectiveScale()
	end

	function LeaMapsZoom.SetPOIMaxBounds()
		LeaMapsZoom.worldmapPoiMaxY = WorldMapDetailFrame:GetHeight() * -WORLDMAP_SETTINGS.size + 12
		LeaMapsZoom.worldmapPoiMaxX = WorldMapDetailFrame:GetWidth()  *  WORLDMAP_SETTINGS.size + 12
	end

	----------------------------------------------------------------------
	-- Core zoom API
	----------------------------------------------------------------------

	function LeaMapsZoom.SetDetailFrameScale(num)
		WorldMapDetailFrame:SetScale(num)
		LeaMapsZoom.SetPOIMaxBounds()

		WorldMapPOIFrame:SetScale(1 / WORLDMAP_SETTINGS.size)
		WorldMapBlobFrame:SetScale(num)

		WorldMapPlayer:SetScale(1 / WorldMapDetailFrame:GetScale())
		WorldMapDeathRelease:SetScale(1 / WorldMapDetailFrame:GetScale())
		WorldMapCorpse:SetScale(1 / WorldMapDetailFrame:GetScale())

		local numFlags = GetNumBattlefieldFlagPositions()
		for i = 1, numFlags do
			local flagFrameName = "WorldMapFlag" .. i
			if _G[flagFrameName] then
				_G[flagFrameName]:SetScale(1 / WorldMapDetailFrame:GetScale())
			end
		end
		for i = 1, MAX_PARTY_MEMBERS do
			if _G["WorldMapParty" .. i] then
				_G["WorldMapParty" .. i]:SetScale(1 / WorldMapDetailFrame:GetScale())
			end
		end
		for i = 1, MAX_RAID_MEMBERS do
			if _G["WorldMapRaid" .. i] then
				_G["WorldMapRaid" .. i]:SetScale(1 / WorldMapDetailFrame:GetScale())
			end
		end
		for i = 1, #MAP_VEHICLES do
			if MAP_VEHICLES[i] then
				MAP_VEHICLES[i]:SetScale(1 / WorldMapDetailFrame:GetScale())
			end
		end

		-- Do NOT fire the DISPLAY_SIZE_CHANGED event here: its handler also
		-- calls WorldMapFrame_UpdateQuests, doubling the heaviest part of
		-- every rescale. Reproduce its only other effect directly.
		WorldMapQuestShowObjectives_AdjustPosition()
		if WorldMapFrame_UpdateQuests() > 0 then
			LeaMapsZoom.RedrawSelectedQuest()
		end
	end

	----------------------------------------------------------------------
	-- Optional addon integration
	----------------------------------------------------------------------

	function LeaMapsZoom.GetElvUI()
		if ElvUI and ElvUI[1] then return ElvUI[1] end
		return nil
	end

	function LeaMapsZoom.GetMapster(configName)
		if LibStub and LibStub:GetLibrary("AceAddon-3.0", true) then
			local mapster = LibStub:GetLibrary("AceAddon-3.0"):GetAddon("Mapster", true)
			if not mapster then return mapster, nil end
			if mapster.db and mapster.db.profile then
				return mapster, mapster.db.profile[configName]
			end
		end
		return nil, nil
	end

	function LeaMapsZoom.ElvUI_SetupWorldMapFrame()
		local worldMap = LeaMapsZoom.GetElvUI():GetModule("WorldMap")
		if not worldMap then return end
		if worldMap.coordsHolder and worldMap.coordsHolder.playerCoords then
			updatePointRelativeTo(worldMap.coordsHolder.playerCoords, WorldMapScrollFrame)
		end
		if WorldMapDetailFrame.backdrop then
			WorldMapDetailFrame.backdrop:Hide()
			local _, worldMapRelativeFrame = WorldMapFrame.backdrop
			if worldMapRelativeFrame == WorldMapDetailFrame then
				updatePointRelativeTo(WorldMapFrame.backdrop, WorldMapScrollFrame)
			end
		end
		if WorldMapFrame.backdrop then
			WorldMapFrame.backdrop.Point = function() return end
			WorldMapFrame.backdrop:ClearAllPoints()
			if WorldMapZoneMinimapDropDown:IsVisible() then
				WorldMapFrame.backdrop:SetPoint("TOPLEFT", WorldMapZoneMinimapDropDown, "TOPLEFT", -20, 40)
			else
				WorldMapFrame.backdrop:SetPoint("TOPLEFT", WorldMapTitleButton, "TOPLEFT", 0, 0)
			end
			WorldMapFrame.backdrop:SetPoint("BOTTOM", WorldMapQuestShowObjectives, "BOTTOM", 0, 0)
			WorldMapFrame.backdrop:SetPoint("RIGHT", WorldMapFrameCloseButton, "RIGHT", 0, 0)
		end
	end

	----------------------------------------------------------------------
	-- Frame setup (called on every OnShow and map-size change)
	----------------------------------------------------------------------

	function LeaMapsZoom.SetupWorldMapFrame()
		WorldMapScrollFrameScrollBar:Hide()
		WorldMapFrame:EnableMouse(true)
		WorldMapScrollFrame:EnableMouse(true)
		WorldMapScrollFrame.panning = false
		WorldMapScrollFrame.moved   = false
		WorldMapScrollFrame.pendingWindowDrag = false
		WorldMapScrollFrame.draggingWindow    = false

		if WORLDMAP_SETTINGS.size == WORLDMAP_QUESTLIST_SIZE then
			WorldMapScrollFrame:SetPoint("TOPLEFT", WorldMapPositioningGuide, "TOP", -726, -99)
			WorldMapTrackQuest:SetPoint("BOTTOMLEFT", WorldMapPositioningGuide, "BOTTOMLEFT", 8, 4)
		elseif WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE then
			WorldMapTrackQuest:SetPoint("BOTTOMLEFT", WorldMapPositioningGuide, "BOTTOMLEFT", 16, -9)
			WorldMapFrame:SetPoint("TOPLEFT", WorldMapScreenAnchor, 0, 0)
			WorldMapFrame:SetScale(WorldMapScreenAnchor.preferredMinimodeScale)
			WorldMapFrame:SetMovable("true")
			WorldMapTitleButton:Show()
			WorldMapTitleButton:ClearAllPoints()
			WorldMapFrameTitle:Show()
			WorldMapFrameTitle:ClearAllPoints()
			WorldMapFrameTitle:SetPoint("CENTER", WorldMapTitleButton, "CENTER", 32, 0)
			if WORLDMAP_SETTINGS.advanced then
				WorldMapScrollFrame:SetPoint("TOPLEFT", 19, -42)
				WorldMapTitleButton:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 13, 0)
			else
				WorldMapScrollFrame:SetPoint("TOPLEFT", 37, -66)
				WorldMapTitleButton:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 13, -14)
			end
		else
			WorldMapScrollFrame:SetPoint("TOPLEFT", WorldMapPositioningGuide, "TOPLEFT", 11, -70.5)
			WorldMapTrackQuest:SetPoint("BOTTOMLEFT", WorldMapPositioningGuide, "BOTTOMLEFT", 16, -9)
		end

		WorldMapScrollFrame:SetScale(WORLDMAP_SETTINGS.size)

		-- Cache Mapster's arrow scale once per setup (used every frame in
		-- WorldMapButton_OnUpdate)
		local _, mapsterArrowScale = LeaMapsZoom.GetMapster("arrowScale")
		LeaMapsZoom._arrowScale = mapsterArrowScale or 1

		-- Pick the target scale up front: SetDetailFrameScale runs a full
		-- quest update, so calling it twice (1 then persisted) doubled the
		-- map-open cost whenever persist zoom was active
		local persistZoom = MagnifyOptions.enablePersistZoom
			and GetCurrentMapZone() == LeaMapsZoom.PreviousState.zone
		LeaMapsZoom.SetDetailFrameScale(persistZoom and LeaMapsZoom.PreviousState.scale or 1)
		WorldMapDetailFrame:SetAllPoints(WorldMapScrollFrame)
		if persistZoom then
			WorldMapScrollFrame:SetHorizontalScroll(LeaMapsZoom.PreviousState.panX)
			WorldMapScrollFrame:SetVerticalScroll(LeaMapsZoom.PreviousState.panY)
		else
			WorldMapScrollFrame:SetHorizontalScroll(0)
			WorldMapScrollFrame:SetVerticalScroll(0)
		end

		WorldMapButton:SetScale(1)
		WorldMapButton:SetAllPoints(WorldMapDetailFrame)
		WorldMapButton:SetParent(WorldMapDetailFrame)

		WorldMapPOIFrame:SetParent(WorldMapDetailFrame)
		WorldMapBlobFrame:SetParent(WorldMapDetailFrame)
		WorldMapBlobFrame:ClearAllPoints()
		WorldMapBlobFrame:SetAllPoints(WorldMapDetailFrame)

		-- Reparenting flattens frame levels (SetParent resets each frame to
		-- parent level + 1), which leaves the blob drawing above the quest
		-- POI buttons. Reassert Blizzard's stock hierarchy (detail < blob <
		-- button < POI frame at WORLDMAP_POI_FRAMELEVEL). Never overwrite
		-- WORLDMAP_POI_FRAMELEVEL: QuestPOI selection code hard-codes it.
		if WorldMapFrame_ResetFrameLevels then
			WorldMapFrame_ResetFrameLevels()
		else
			WorldMapBlobFrame:SetFrameLevel(WorldMapButton:GetFrameLevel() + 1)
			WorldMapPOIFrame:SetFrameLevel(WorldMapButton:GetFrameLevel() + 2)
		end

		WorldMapBlobFrame:SetFillAlpha(LeaMapsZoom.BLOB_FILL_ALPHA)
		WorldMapBlobFrame:SetBorderAlpha(LeaMapsZoom.BLOB_BORDER_ALPHA)

		WorldMapPlayer:SetParent(WorldMapDetailFrame)

		updatePointRelativeTo(WorldMapQuestScrollFrame,       WorldMapScrollFrame)
		updatePointRelativeTo(WorldMapQuestDetailScrollFrame, WorldMapScrollFrame)

		-- The quest-list layout is disabled (see Leatrix_Maps.lua), so the
		-- quest panels must never be visible outside of it
		if WORLDMAP_SETTINGS.size ~= WORLDMAP_QUESTLIST_SIZE then
			if WorldMapQuestScrollFrame then WorldMapQuestScrollFrame:Hide() end
			if WorldMapQuestDetailScrollFrame then WorldMapQuestDetailScrollFrame:Hide() end
			if WorldMapQuestRewardScrollFrame then WorldMapQuestRewardScrollFrame:Hide() end
		end

		if LeaMapsZoom.GetElvUI() then
			LeaMapsZoom.ElvUI_SetupWorldMapFrame()
		end
	end

	----------------------------------------------------------------------
	-- Mouse handlers
	----------------------------------------------------------------------

	function LeaMapsZoom.WorldMapScrollFrame_OnPan(cursorX, cursorY)
		local dX = WorldMapScrollFrame.cursorX - cursorX
		local dY = cursorY - WorldMapScrollFrame.cursorY
		dX = dX / this:GetEffectiveScale()
		dY = dY / this:GetEffectiveScale()
		if abs(dX) >= 1 or abs(dY) >= 1 then
			WorldMapScrollFrame.moved = true
			local x = max(0, dX + WorldMapScrollFrame.x)
			x = min(x, WorldMapScrollFrame.maxX)
			WorldMapScrollFrame:SetHorizontalScroll(x)
			local y = max(0, dY + WorldMapScrollFrame.y)
			y = min(y, WorldMapScrollFrame.maxY)
			WorldMapScrollFrame:SetVerticalScroll(y)
			LeaMapsZoom.AfterScrollOrPan()
		end
	end

	function LeaMapsZoom.WorldMapScrollFrame_OnMouseWheel()
		-- Ctrl+scroll in mini mode: zoom the whole frame
		if IsControlKeyDown() and WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE then
			local oldScale = WorldMapFrame:GetScale()
			local newScale = oldScale + arg1 * LeaMapsZoom.MINIMODE_ZOOM_STEP
			newScale = max(LeaMapsZoom.MINIMODE_MIN_ZOOM, newScale)
			newScale = min(LeaMapsZoom.MINIMODE_MAX_ZOOM, newScale)
			WorldMapFrame:SetScale(newScale)
			WorldMapScreenAnchor.preferredMinimodeScale = newScale
			LeaMapsZoom.RepaintBlob()
			LeaMapsZoom.RefreshQuestPOIs()
			return
		end

		local oldScrollH = this:GetHorizontalScroll()
		local oldScrollV = this:GetVerticalScroll()

		local cursorX, cursorY = GetCursorPosition()
		cursorX = cursorX / this:GetEffectiveScale()
		cursorY = cursorY / this:GetEffectiveScale()

		local frameX = cursorX - this:GetLeft()
		local frameY = this:GetTop() - cursorY

		local oldScale = WorldMapDetailFrame:GetScale()
		local newScale = oldScale * (1.0 + arg1 * MagnifyOptions.zoomStep)
		newScale = max(LeaMapsZoom.MIN_ZOOM, newScale)
		newScale = min(MagnifyOptions.maxZoom, newScale)

		LeaMapsZoom.SetDetailFrameScale(newScale)

		this.maxX = ((WorldMapDetailFrame:GetWidth()  * newScale) - this:GetWidth())  / newScale
		this.maxY = ((WorldMapDetailFrame:GetHeight() * newScale) - this:GetHeight()) / newScale
		this.zoomedIn = WorldMapDetailFrame:GetScale() > LeaMapsZoom.MIN_ZOOM

		local centerX    = oldScrollH + frameX / oldScale
		local centerY    = oldScrollV + frameY / oldScale
		local newScrollH = centerX - frameX / newScale
		local newScrollV = centerY - frameY / newScale

		newScrollH = min(max(0, newScrollH), this.maxX)
		newScrollV = min(max(0, newScrollV), this.maxY)

		this:SetHorizontalScroll(newScrollH)
		this:SetVerticalScroll(newScrollV)
		LeaMapsZoom.AfterScrollOrPan()
	end

	-- Sync the screen anchor and persist the window position so the main
	-- addon's OnShow hook restores the map where the player left it
	function LeaMapsZoom.SaveWindowPosition()
		WorldMapScreenAnchor:StartMoving()
		WorldMapScreenAnchor:SetPoint("TOPLEFT", WorldMapFrame)
		WorldMapScreenAnchor:StopMovingOrSizing()
		if LeaMapsLC then
			local a, _, r, x, y = WorldMapFrame:GetPoint()
			LeaMapsLC["MapPosA"], LeaMapsLC["MapPosR"], LeaMapsLC["MapPosX"], LeaMapsLC["MapPosY"] = a, r, x, y
		end
	end

	function LeaMapsZoom.WorldMapButton_OnMouseDown()
		if arg1 == "LeftButton" and WorldMapScrollFrame.zoomedIn then
			WorldMapScrollFrame.panning  = true
			local x, y = GetCursorPosition()
			WorldMapScrollFrame.cursorX  = x
			WorldMapScrollFrame.cursorY  = y
			WorldMapScrollFrame.x        = WorldMapScrollFrame:GetHorizontalScroll()
			WorldMapScrollFrame.y        = WorldMapScrollFrame:GetVerticalScroll()
			WorldMapScrollFrame.moved    = false
		elseif arg1 == "LeftButton"
			and LeaMapsLC and LeaMapsLC["UnlockMapFrame"] == "On"
			and WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE then
			-- Not zoomed in: left-drag on the map canvas moves the window.
			-- StartMoving is deferred until the cursor travels a few pixels
			-- (see WorldMapButton_OnUpdate) so a plain click never nudges
			-- the window or blinks the objective glow
			local x, y = GetCursorPosition()
			WorldMapScrollFrame.dragX = x
			WorldMapScrollFrame.dragY = y
			WorldMapScrollFrame.pendingWindowDrag = true
		end
	end

	function LeaMapsZoom.WorldMapButton_OnMouseUp()
		WorldMapScrollFrame.pendingWindowDrag = false
		if WorldMapScrollFrame.draggingWindow then
			WorldMapScrollFrame.draggingWindow = false
			WorldMapFrame:StopMovingOrSizing()
			WorldMapFrame:SetUserPlaced(false)
			LeaMapsZoom.SaveWindowPosition()
			LeaMapsZoom.EndWindowDrag()
			-- The drag only starts after the movement threshold, so this
			-- was a real drag, never a click
			WorldMapScrollFrame.moved = true
		end
		WorldMapScrollFrame.panning = false
		if not WorldMapScrollFrame.moved then
			WorldMapButton_OnClick(WorldMapButton, arg1)
			LeaMapsZoom.SetDetailFrameScale(LeaMapsZoom.MIN_ZOOM)
			WorldMapScrollFrame:SetHorizontalScroll(0)
			WorldMapScrollFrame:SetVerticalScroll(0)
			LeaMapsZoom.AfterScrollOrPan()
			WorldMapScrollFrame.zoomedIn = false
		end
		WorldMapScrollFrame.moved = false
	end

	----------------------------------------------------------------------
	-- OnUpdate: player/party/vehicle positions (runs every frame)
	----------------------------------------------------------------------

	function LeaMapsZoom.WorldMapButton_OnUpdate(self, elapsed)
		-- Deferred window-drag start (see WorldMapButton_OnMouseDown)
		if WorldMapScrollFrame.pendingWindowDrag then
			local px, py = GetCursorPosition()
			if abs(px - (WorldMapScrollFrame.dragX or px)) >= 5
			or abs(py - (WorldMapScrollFrame.dragY or py)) >= 5 then
				WorldMapScrollFrame.pendingWindowDrag = false
				WorldMapScrollFrame.draggingWindow = true
				LeaMapsZoom.BeginWindowDrag()
				WorldMapScreenAnchor:ClearAllPoints()
				WorldMapFrame:ClearAllPoints()
				WorldMapFrame:StartMoving()
			end
		end

		local x, y = GetCursorPosition()
		x = x / self:GetEffectiveScale()
		y = y / self:GetEffectiveScale()

		local centerX, centerY = self:GetCenter()
		local width  = self:GetWidth()
		local height = self:GetHeight()
		local adjustedY = (centerY + (height / 2) - y) / height
		local adjustedX = (x - (centerX - (width / 2))) / width

		local name, fileName, texPercentageX, texPercentageY, textureX, textureY, scrollChildX, scrollChildY
		if self:IsMouseOver() then
			name, fileName, texPercentageX, texPercentageY, textureX, textureY, scrollChildX, scrollChildY =
				UpdateMapHighlight(adjustedX, adjustedY)
		end

		WorldMapFrame.areaName = name
		if not WorldMapFrame.poiHighlight then
			WorldMapFrameAreaLabel:SetText(name)
		end
		if fileName then
			WorldMapHighlight:SetTexCoord(0, texPercentageX, 0, texPercentageY)
			WorldMapHighlight:SetTexture("Interface\\WorldMap\\" .. fileName .. "\\" .. fileName .. "Highlight")
			textureX    = textureX    * width
			textureY    = textureY    * height
			scrollChildX = scrollChildX * width
			scrollChildY = -scrollChildY * height
			if textureX > 0 and textureY > 0 then
				WorldMapHighlight:SetWidth(textureX)
				WorldMapHighlight:SetHeight(textureY)
				WorldMapHighlight:SetPoint("TOPLEFT", "WorldMapDetailFrame", "TOPLEFT", scrollChildX, scrollChildY)
				WorldMapHighlight:Show()
			end
		else
			WorldMapHighlight:Hide()
		end

		-- Player position
		UpdateWorldMapArrowFrames()
		local playerX, playerY = GetPlayerMapPosition("player")
		if playerX == 0 and playerY == 0 then
			ShowWorldMapArrowFrame(nil)
			WorldMapPing:Hide()
			WorldMapPlayer:Hide()
		else
			playerX = playerX * WorldMapDetailFrame:GetWidth()  * WorldMapDetailFrame:GetScale() * WORLDMAP_SETTINGS.size
			playerY = -playerY * WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale() * WORLDMAP_SETTINGS.size
			PositionWorldMapArrowFrame("CENTER", "WorldMapDetailFrame", "TOPLEFT", playerX, playerY)
			ShowWorldMapArrowFrame(nil)
			WorldMapPlayer:SetAllPoints(PlayerArrowFrame)
			WorldMapPlayer.Icon:SetRotation(PlayerArrowFrame:GetFacing())
			-- Arrow scale is cached in SetupWorldMapFrame — looking Mapster
			-- up through LibStub every frame caused measurable overhead
			local arrowSize = LeaMapsZoom.PLAYER_ARROW_SIZE * (LeaMapsZoom._arrowScale or 1)
			if LeaMapsZoom._lastArrowSize ~= arrowSize then
				LeaMapsZoom._lastArrowSize = arrowSize
				WorldMapPlayer.Icon:SetSize(arrowSize, arrowSize)
			end
			WorldMapPlayer:Show()
		end

		-- Party / raid positions
		local playerCount = 0
		if GetNumRaidMembers() > 0 then
			for i = 1, MAX_PARTY_MEMBERS do _G["WorldMapParty" .. i]:Hide() end
			for i = 1, MAX_RAID_MEMBERS do
				local unit = "raid" .. i
				local partyX, partyY = GetPlayerMapPosition(unit)
				local partyMemberFrame = _G["WorldMapRaid" .. (playerCount + 1)]
				if (partyX == 0 and partyY == 0) or UnitIsUnit(unit, "player") then
					partyMemberFrame:Hide()
				else
					partyX = partyX * WorldMapDetailFrame:GetWidth()  * WorldMapDetailFrame:GetScale()
					partyY = -partyY * WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale()
					partyMemberFrame:SetPoint("CENTER", "WorldMapDetailFrame", "TOPLEFT", partyX, partyY)
					partyMemberFrame.name = nil
					partyMemberFrame.unit = unit
					LeaMapsZoom.ColorWorldMapPartyMemberFrame(partyMemberFrame, unit)
					partyMemberFrame:Show()
					playerCount = playerCount + 1
				end
			end
		else
			for i = 1, MAX_PARTY_MEMBERS do
				local partyX, partyY = GetPlayerMapPosition("party" .. i)
				local partyMemberFrame = _G["WorldMapParty" .. i]
				if partyX == 0 and partyY == 0 then
					partyMemberFrame:Hide()
				else
					partyX = partyX * WorldMapButton:GetWidth()  * WorldMapDetailFrame:GetScale()
					partyY = -partyY * WorldMapButton:GetHeight() * WorldMapDetailFrame:GetScale()
					partyMemberFrame:SetPoint("CENTER", "WorldMapButton", "TOPLEFT", partyX, partyY)
					LeaMapsZoom.ColorWorldMapPartyMemberFrame(partyMemberFrame, "party" .. i)
					partyMemberFrame:Show()
				end
			end
		end

		-- BG team members
		local numTeamMembers = GetNumBattlefieldPositions()
		for i = playerCount + 1, MAX_RAID_MEMBERS do
			local partyX, partyY, name = GetBattlefieldPosition(i - playerCount)
			local partyMemberFrame = _G["WorldMapRaid" .. i]
			if partyX == 0 and partyY == 0 then
				partyMemberFrame:Hide()
			else
				partyX = partyX * WorldMapDetailFrame:GetWidth()  * WorldMapDetailFrame:GetScale()
				partyY = -partyY * WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale()
				partyMemberFrame:SetPoint("CENTER", "WorldMapDetailFrame", "TOPLEFT", partyX, partyY)
				partyMemberFrame.name  = name
				partyMemberFrame.unit  = nil
				partyMemberFrame.colorIcon:Hide()
				partyMemberFrame.icon:Show()
				partyMemberFrame:Show()
			end
		end

		-- Battlefield flags
		local numFlags = GetNumBattlefieldFlagPositions()
		for i = 1, numFlags do
			local flagX, flagY, flagToken = GetBattlefieldFlagPosition(i)
			local flagFrameName = "WorldMapFlag" .. i
			local flagFrame     = _G[flagFrameName]
			if flagX == 0 and flagY == 0 then
				flagFrame:Hide()
			else
				flagX = flagX * WorldMapDetailFrame:GetWidth()  * WorldMapDetailFrame:GetScale()
				flagY = -flagY * WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale()
				flagFrame:SetPoint("CENTER", "WorldMapDetailFrame", "TOPLEFT", flagX, flagY)
				_G[flagFrameName .. "Texture"]:SetTexture("Interface\\WorldStateFrame\\" .. flagToken)
				flagFrame:Show()
			end
		end
		for i = numFlags + 1, NUM_WORLDMAP_FLAGS do
			_G["WorldMapFlag" .. i]:Hide()
		end

		-- Corpse
		local corpseX, corpseY = GetCorpseMapPosition()
		if corpseX == 0 and corpseY == 0 then
			WorldMapCorpse:Hide()
		else
			corpseX = corpseX * WorldMapDetailFrame:GetWidth()  * WorldMapDetailFrame:GetScale()
			corpseY = -corpseY * WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale()
			WorldMapCorpse:SetPoint("CENTER", "WorldMapDetailFrame", "TOPLEFT", corpseX, corpseY)
			WorldMapCorpse:Show()
		end

		-- Death release
		local deathReleaseX, deathReleaseY = GetDeathReleasePosition()
		if (deathReleaseX == 0 and deathReleaseY == 0) or UnitIsGhost("player") then
			WorldMapDeathRelease:Hide()
		else
			deathReleaseX = deathReleaseX * WorldMapDetailFrame:GetWidth()  * WorldMapDetailFrame:GetScale()
			deathReleaseY = -deathReleaseY * WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale()
			WorldMapDeathRelease:SetPoint("CENTER", "WorldMapDetailFrame", "TOPLEFT", deathReleaseX, deathReleaseY)
			WorldMapDeathRelease:Show()
		end

		-- Vehicles
		local numVehicles
		if GetCurrentMapContinent() == WORLDMAP_WORLD_ID or
		   (GetCurrentMapContinent() ~= -1 and GetCurrentMapZone() == 0) then
			numVehicles = 0
		else
			numVehicles = GetNumBattlefieldVehicles()
		end
		local totalVehicles = #MAP_VEHICLES
		local index = 0
		for i = 1, numVehicles do
			if i > totalVehicles then
				local vehicleName = "WorldMapVehicles" .. i
				MAP_VEHICLES[i] = CreateFrame("FRAME", vehicleName, WorldMapButton, "WorldMapVehicleTemplate")
				MAP_VEHICLES[i].texture = _G[vehicleName .. "Texture"]
			end
			local vehicleX, vehicleY, unitName, isPossessed, vehicleType, orientation, isPlayer, isAlive =
				GetBattlefieldVehicleInfo(i)
			if vehicleX and isAlive and not isPlayer and VEHICLE_TEXTURES[vehicleType] then
				local mapVehicleFrame = MAP_VEHICLES[i]
				vehicleX = vehicleX * WorldMapDetailFrame:GetWidth()  * WorldMapDetailFrame:GetScale()
				vehicleY = -vehicleY * WorldMapDetailFrame:GetHeight() * WorldMapDetailFrame:GetScale()
				mapVehicleFrame.texture:SetRotation(orientation)
				mapVehicleFrame.texture:SetTexture(WorldMap_GetVehicleTexture(vehicleType, isPossessed))
				mapVehicleFrame:SetPoint("CENTER", "WorldMapDetailFrame", "TOPLEFT", vehicleX, vehicleY)
				mapVehicleFrame:SetWidth(VEHICLE_TEXTURES[vehicleType].width)
				mapVehicleFrame:SetHeight(VEHICLE_TEXTURES[vehicleType].height)
				mapVehicleFrame.name = unitName
				mapVehicleFrame:Show()
				index = i
			else
				MAP_VEHICLES[i]:Hide()
			end
		end
		if index < totalVehicles then
			for i = index + 1, totalVehicles do MAP_VEHICLES[i]:Hide() end
		end

		if WorldMapScrollFrame.panning then
			LeaMapsZoom.WorldMapScrollFrame_OnPan(GetCursorPosition())
		end
	end

	----------------------------------------------------------------------
	-- Misc helpers
	----------------------------------------------------------------------

	function LeaMapsZoom.RedrawSelectedQuest()
		if WORLDMAP_SETTINGS.selectedQuestId then
			WorldMapFrame_SelectQuestById(WORLDMAP_SETTINGS.selectedQuestId)
		else
			WorldMapFrame_SelectQuestFrame(_G["WorldMapQuestFrame1"])
		end
	end

	-- Quest POI button sizes are computed against the map frame's effective
	-- scale (in resizePOI), so any change to the frame's own scale AFTER the
	-- last WorldMapFrame_UpdateQuests leaves them the wrong size until the
	-- next quest update. Force one immediately; Blizzard re-anchors the
	-- buttons and the ResizeQuestPOIs hook re-scales them. (Never call
	-- resizePOI directly here — its position math is only valid right after
	-- Blizzard has reset the button anchors.)
	function LeaMapsZoom.RefreshQuestPOIs()
		if WorldMapFrame:IsShown() and WorldMapFrame_UpdateQuests then
			-- Sizes are already correct for the current scale — skip the
			-- (expensive) quest update entirely
			if LeaMapsZoom._resizedAtScale == WorldMapDetailFrame:GetEffectiveScale() then
				return
			end
			if (WorldMapFrame_UpdateQuests() or 0) > 0 then
				LeaMapsZoom.RedrawSelectedQuest()
			end
		end
	end

	function LeaMapsZoom.ColorWorldMapPartyMemberFrame(partyMemberFrame, unit)
		local classColor = RAID_CLASS_COLORS[select(2, UnitClass(unit))]
		if classColor and not MagnifyOptions.enableOldPartyIcons then
			partyMemberFrame.colorIcon:Show()
			partyMemberFrame.icon:Hide()
			partyMemberFrame.colorIcon:SetVertexColor(classColor.r, classColor.g, classColor.b, 1)
		else
			partyMemberFrame.colorIcon:Hide()
			partyMemberFrame.icon:Show()
		end
	end

	function LeaMapsZoom.CreateClassColorIcon(partyMemberFrame)
		if partyMemberFrame then
			partyMemberFrame.colorIcon = partyMemberFrame:CreateTexture(nil, "ARTWORK")
			partyMemberFrame.colorIcon:SetAllPoints(partyMemberFrame)
			partyMemberFrame.colorIcon:SetTexture(
				"Interface\\AddOns\\" .. ADDON_NAME .. "\\textures\\WorldMapPlayer")
			partyMemberFrame.icon:Hide()
		end
	end

	----------------------------------------------------------------------
	-- Initialization (called from Leatrix_Maps.lua MainFunc)
	----------------------------------------------------------------------

	function LeaMapsZoom.OnFirstLoad()
		-- Ensure option defaults
		MagnifyOptions.enablePersistZoom   = MagnifyOptions.enablePersistZoom   or LeaMapsZoom.ENABLEPERSISTZOOM_DEFAULT
		MagnifyOptions.enableOldPartyIcons = MagnifyOptions.enableOldPartyIcons or LeaMapsZoom.ENABLEOLDPARTYICONS_DEFAULT
		MagnifyOptions.maxZoom             = MagnifyOptions.maxZoom             or LeaMapsZoom.MAXZOOM_DEFAULT
		MagnifyOptions.zoomStep            = MagnifyOptions.zoomStep            or LeaMapsZoom.ZOOMSTEP_DEFAULT

		-- Mapster compatibility: disable its POI handling once here (this
		-- was previously re-applied for every POI button on every quest
		-- update, with a LibStub lookup each time)
		local mapster = LeaMapsZoom.GetMapster()
		if mapster then
			mapster.WorldMapFrame_DisplayQuestPOI = function() end
		end

		WorldMapScrollFrame:SetScrollChild(WorldMapDetailFrame)
		WorldMapScrollFrame:SetScript("OnMouseWheel", LeaMapsZoom.WorldMapScrollFrame_OnMouseWheel)
		WorldMapButton:SetScript("OnMouseDown", LeaMapsZoom.WorldMapButton_OnMouseDown)
		WorldMapButton:SetScript("OnMouseUp",   LeaMapsZoom.WorldMapButton_OnMouseUp)
		WorldMapDetailFrame:SetParent(WorldMapScrollFrame)

		WorldMapFrameAreaFrame:SetParent(WorldMapFrame)
		WorldMapFrameAreaFrame:SetFrameLevel(WORLDMAP_POI_FRAMELEVEL)
		WorldMapFrameAreaFrame:SetPoint("TOP", WorldMapScrollFrame, "TOP", 0, -10)

		-- Disable the ping effect (doesn't work correctly when zoomed)
		WorldMapPing.Show = function() return end
		WorldMapPing:SetModelScale(0)

		-- Higher-resolution player arrow that clips correctly when panned
		WorldMapPlayer.Icon = WorldMapPlayer:CreateTexture(nil, "ARTWORK")
		WorldMapPlayer.Icon:SetSize(LeaMapsZoom.PLAYER_ARROW_SIZE, LeaMapsZoom.PLAYER_ARROW_SIZE)
		WorldMapPlayer.Icon:SetPoint("CENTER", 0, 0)
		WorldMapPlayer.Icon:SetTexture(
			"Interface\\AddOns\\" .. ADDON_NAME .. "\\textures\\WorldMapArrow")

		hooksecurefunc("WorldMapFrame_SetFullMapView",  LeaMapsZoom.SetupWorldMapFrame)
		hooksecurefunc("WorldMapFrame_SetQuestMapView", LeaMapsZoom.SetupWorldMapFrame)
		hooksecurefunc("WorldMap_ToggleSizeDown",       LeaMapsZoom.SetupWorldMapFrame)
		hooksecurefunc("WorldMap_ToggleSizeUp",         LeaMapsZoom.SetupWorldMapFrame)
		hooksecurefunc("WorldMapFrame_UpdateQuests",    LeaMapsZoom.ResizeQuestPOIs)
		hooksecurefunc("WorldMapFrame_SetPOIMaxBounds", LeaMapsZoom.SetPOIMaxBounds)

		hooksecurefunc("WorldMapQuestShowObjectives_AdjustPosition", function()
			if WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE then
				WorldMapQuestShowObjectives:SetPoint("BOTTOMRIGHT", WorldMapPositioningGuide, "BOTTOMRIGHT",
					-30 - WorldMapQuestShowObjectivesText:GetWidth(), -9)
			else
				WorldMapQuestShowObjectives:SetPoint("BOTTOMRIGHT", WorldMapPositioningGuide, "BOTTOMRIGHT",
					-15 - WorldMapQuestShowObjectivesText:GetWidth(), 4)
			end
		end)

		WorldMapScreenAnchor:StartMoving()
		WorldMapScreenAnchor:SetPoint("TOPLEFT", 10, -118)
		WorldMapScreenAnchor:StopMovingOrSizing()
		WorldMapScreenAnchor.preferredMinimodeScale =
			1 + (0.4 * WorldMapFrame:GetHeight() / WorldFrame:GetHeight())

		-- Title button drag — move the whole frame (keeps anchor in sync)
		WorldMapTitleButton:SetScript("OnDragStart", function()
			LeaMapsZoom.BeginWindowDrag()
			WorldMapScreenAnchor:ClearAllPoints()
			WorldMapFrame:ClearAllPoints()
			WorldMapFrame:StartMoving()
		end)
		WorldMapTitleButton:SetScript("OnDragStop", function()
			WorldMapFrame:StopMovingOrSizing()
			WorldMapFrame:SetUserPlaced(false)
			LeaMapsZoom.SaveWindowPosition()
			LeaMapsZoom.EndWindowDrag()
		end)

		WorldMapButton:SetScript("OnUpdate", LeaMapsZoom.WorldMapButton_OnUpdate)

		-- Wrap Blizzard's OnShow so SetupWorldMapFrame fires on every map open
		local original_WorldMapFrame_OnShow = WorldMapFrame:GetScript("OnShow")
		WorldMapFrame:SetScript("OnShow", function(self)
			original_WorldMapFrame_OnShow(self)
			LeaMapsZoom.SetupWorldMapFrame()
		end)

		-- Colour party/raid icons by class
		for i = 1, MAX_RAID_MEMBERS do
			LeaMapsZoom.CreateClassColorIcon(_G["WorldMapParty" .. i])
			LeaMapsZoom.CreateClassColorIcon(_G["WorldMapRaid"  .. i])
		end
	end

