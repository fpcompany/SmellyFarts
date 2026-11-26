local ADDON_NAME = ...

-- Plays a sound whenever an enemy player character dies. Deaths are detected
-- from the unit's own state (alive -> dead transition) on the units the client
-- lets addons see -- target, focus, nameplates, arena opponents -- since the
-- combat log is closed to addons. An enemy that dies with none of those
-- pointing at it (no nameplate shown, not targeted) can't be noticed.

local MEDIA = 'Interface\\AddOns\\' .. ADDON_NAME .. '\\Media\\'
local SOUNDS = {
	{ name = 'Fart', file = MEDIA .. 'fart.mp3' },
	{ name = 'Wet fart', file = MEDIA .. 'wet_fart.ogg' },
	{ name = 'Wilhelm scream', file = MEDIA .. 'wilhelm_scream.ogg' },
	{ name = 'Minecraft oof', file = MEDIA .. 'minecraft_oof.ogg' },
	{ name = 'Roblox oof', file = MEDIA .. 'roblox_oof.ogg' },
	{ name = 'Fart with extra reverb', file = MEDIA .. 'fart-with-extra-reverb.ogg' },
	{ name = 'Bass-boosted fart', file = MEDIA .. 'fart-with-reverb-and-bass-boost.ogg' },
	{ name = 'Fart squeak', file = MEDIA .. 'fart-squeak-reverb.ogg' },
	{ name = 'Ahhhh', file = MEDIA .. 'ahhhh-gachi-muchi.ogg' },
	{ name = 'Faaaa', file = MEDIA .. 'faaaa.ogg' },
	{ name = 'Lego Yoda death', file = MEDIA .. 'lego-yoda-death-sound-effect.ogg' },
	{ name = 'Slap', file = MEDIA .. 'slap.ogg' },
	{ name = 'TF2 domination', file = MEDIA .. 'tf_domination.ogg' },
	{ name = 'Windows XP shutdown', file = MEDIA .. 'windows_xp_shutdown.ogg' },
	{ name = 'Tom scream', file = MEDIA .. 'tom-scream-01.ogg' },
	{ name = 'MLG air horn', file = MEDIA .. 'mlg_air_horn.ogg' },
	{ name = 'Jackpot', file = MEDIA .. 'jackpot.mp3' },
	{ name = 'GTA V wasted', file = MEDIA .. 'gta5_wasted.mp3' },
	{ name = 'Half-Life 2 combine death', file = MEDIA .. 'hl2_combine_death.mp3' },
	{ name = 'Half-Life 2 flatline', file = MEDIA .. 'hl2_flatline.mp3' },
	{ name = 'League of Legends announce', file = MEDIA .. 'lol_announce.mp3' },
	{ name = 'Toilet flush', file = MEDIA .. 'toilet_flush.mp3' },
}
local ICON = MEDIA .. 'Icon'

local defaults = {
	enabled = true,
	minimapAngle = 220,
}

local db
local units = {} -- [guid or unit token] = { dead = bool, enemy = bool }
local debugMode = false

local issecretvalue = _G.issecretvalue or function() return false end

local function Debug(fmt, ...)
	if debugMode then
		print(('|cff1784d1SF|r |cff999999%.2f|r ' .. fmt):format(GetTime() % 100, ...))
	end
end

--------------------------------------------------------------------------------
-- Detection
--------------------------------------------------------------------------------

-- returns whether the client accepted the sound (false when sound is off, the
-- file is missing, or every sound channel is busy) and its handle
local function PlayEntry(sound)
	local willPlay, handle = PlaySoundFile(sound.file, 'Master')
	Debug('play %s%s', sound.name, willPlay and '' or ' |cffff0000(not played)|r')
	return willPlay, handle
end

local function Known(value)
	return value ~= nil and not issecretvalue(value)
end

-- Every party member should hear the same sound for the same death, without
-- the clients talking to each other. So the sound is picked from what all of
-- them agree on: who died (GUID, or name-realm) and the server time cut into
-- windows. The window makes a given enemy's sound change over time; clients
-- disagree only when a death lands right on a window edge.
local SYNC_WINDOW = 180 -- seconds

-- djb2 plus a few rounds of squaring mod a prime, since plain djb2 just steps
-- through the sounds in order as the window number counts up. Everything
-- stays below 2^53, so the math is exact and every client gets the same number.
local HASH_PRIME = 67108859 -- < 2^26, so squares stay exact in a double
local function HashIndex(str, n)
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + str:byte(i)) % 4294967296
	end
	h = h % HASH_PRIME
	for _ = 1, 3 do
		h = (h * h + 7919) % HASH_PRIME
	end
	return h % n + 1
end

-- an identity string that's the same on every client, or nil
local function SharedId(unit)
	local guid = UnitGUID(unit)
	if Known(guid) then return guid end
	local name, realm = UnitName(unit)
	if Known(name) and not issecretvalue(realm) then
		-- realm is nil when the unit is on the observer's realm, which
		-- differs between observers
		if not realm or realm == '' then realm = GetNormalizedRealmName() end
		if realm then return name .. '-' .. realm end
	end
end

local function PickSound(unit)
	local id = unit and SharedId(unit)
	if not id then
		Debug('no shared id, picking at random')
		return SOUNDS[math.random(#SOUNDS)]
	end
	local bucket = math.floor(GetServerTime() / SYNC_WINDOW)
	return SOUNDS[HashIndex(id .. ':' .. bucket, #SOUNDS)]
end

local function PlayDeathSound(unit)
	PlayEntry(PickSound(unit))
end

-- Only these unit tokens are looked at. Others (targettarget, ...) are copies
-- of these and would only produce duplicates or secret values.
local function IsWatchedToken(unit)
	return unit == 'target' or unit == 'focus'
		or unit:find('^nameplate%d+$') or unit:find('^arena%d+$')
end

-- state key: the GUID when the client gives it out (the same player can be
-- target, focus and a nameplate at once), otherwise the token itself
local function UnitKey(unit)
	if type(unit) ~= 'string' or not IsWatchedToken(unit) then return end
	local exists = UnitExists(unit)
	if not Known(exists) or not exists then return end
	local isPlayer = UnitIsPlayer(unit)
	if not Known(isPlayer) or not isPlayer then return end
	local guid = UnitGUID(unit)
	if Known(guid) then return guid end
	return unit
end

-- dead players can't be attacked, so hostility is remembered from while they
-- were alive as well as checked now
local function IsEnemyNow(unit)
	local enemy = UnitIsEnemy('player', unit)
	if Known(enemy) and enemy then return true end
	local attackable = UnitCanAttack('player', unit)
	return Known(attackable) and attackable or false
end

local function IsDead(unit)
	local dead = UnitIsDeadOrGhost(unit)
	if issecretvalue(dead) then return nil end
	if dead and UnitIsFeignDeath then
		local feign = UnitIsFeignDeath(unit)
		if issecretvalue(feign) then return nil end
		if feign then return false end
	end
	return dead and true or false
end

-- Hunters. UnitIsFeignDeath only answers for group members; to an enemy a
-- feigning hunter just looks dead. What tells a real death apart is that
-- we're awarded honor (Feign Death gives none). The honor message doesn't
-- name the hunter -- it's just "You have been awarded 3 Honor." -- so it's
-- matched by timing: a hunter death counts only when honor comes in within
-- SAME_MOMENT of it. A feign that coincides with another honorable kill can
-- still slip through; a hunter killed without honor for us stays silent.
local SAME_MOMENT = 1.5 -- seconds; honor was seen arriving 1.0s after death
local pendingHunters = {} -- { time = GetTime(), sound = entry, name = string }
local honorTimes = {} -- GetTime() of unclaimed honor awards

local function IsHunter(unit)
	local _, class = UnitClass(unit)
	return Known(class) and class == 'HUNTER'
end

-- index of the oldest time in list within SAME_MOMENT of t
local function FindWithin(list, t)
	for i, x in ipairs(list) do
		if math.abs(x - t) <= SAME_MOMENT then return i end
	end
end

local function MatchHunters()
	local now = GetTime()
	local i = 1
	while pendingHunters[i] do
		local hunter = pendingHunters[i]
		local h = FindWithin(honorTimes, hunter.time)
		if h then
			Debug('%s: honor in, real death', hunter.name)
			tremove(honorTimes, h)
			tremove(pendingHunters, i)
			PlayEntry(hunter.sound)
		elseif now - hunter.time > SAME_MOMENT then
			Debug('%s: no honor, feign death? no sound', hunter.name)
			tremove(pendingHunters, i)
		else
			i = i + 1
		end
	end
	-- anything older than the window can't match a later event
	while honorTimes[1] and now - honorTimes[1] > SAME_MOMENT do tremove(honorTimes, 1) end
end

-- check now, and again once the window has passed
local function Record(list, entry)
	tinsert(list, entry)
	MatchHunters()
	C_Timer.After(SAME_MOMENT + 0.1, MatchHunters)
end

local function OnHunterDeath(unit)
	local name = tostring(UnitName(unit))
	Debug('waiting for honor for %s', name)
	-- picked now, from the unit, so the party still hears the same sound
	Record(pendingHunters, { time = GetTime(), sound = PickSound(unit), name = name })
end

local function OnHonorGain()
	Debug('honor in')
	Record(honorTimes, GetTime())
end

local function CheckUnit(unit, silent)
	local key = UnitKey(unit)
	if not key then return end
	local dead = IsDead(unit)
	if dead == nil then return end

	local state = units[key]
	if not state then
		state = { dead = dead, enemy = false }
		units[key] = state
		silent = true -- first sighting: someone already dead isn't a new death
	end
	if silent and not dead then
		-- (re)sighting: a token key may now point at a different person
		state.enemy = IsEnemyNow(unit)
	elseif not dead and IsEnemyNow(unit) then
		state.enemy = true
	end

	if dead and not state.dead and not silent and (state.enemy or IsEnemyNow(unit)) then
		Debug('%s died', tostring(UnitName(unit)))
		if IsHunter(unit) then
			OnHunterDeath(unit)
		else
			PlayDeathSound(unit)
		end
	end
	state.dead = dead
end

local function CheckAll()
	CheckUnit('target', true)
	CheckUnit('focus', true)
	for i = 1, 40 do CheckUnit('nameplate' .. i, true) end
	for i = 1, 5 do CheckUnit('arena' .. i, true) end
end

local events = CreateFrame('Frame')

local function UpdateEvents()
	events:UnregisterAllEvents()
	events:RegisterEvent('ADDON_LOADED')
	if db and db.enabled then
		events:RegisterEvent('UNIT_HEALTH')
		events:RegisterEvent('UNIT_FLAGS')
		events:RegisterEvent('NAME_PLATE_UNIT_ADDED')
		events:RegisterEvent('PLAYER_TARGET_CHANGED')
		events:RegisterEvent('PLAYER_FOCUS_CHANGED')
		events:RegisterEvent('ARENA_OPPONENT_UPDATE')
		events:RegisterEvent('PLAYER_ENTERING_WORLD')
		events:RegisterEvent('CHAT_MSG_COMBAT_HONOR_GAIN')
		wipe(units)
		wipe(pendingHunters)
		wipe(honorTimes)
		CheckAll()
	end
end

--------------------------------------------------------------------------------
-- Sound test panel
--------------------------------------------------------------------------------

local panel

local function SetDebug(enabled)
	debugMode = enabled
	if panel then panel.debugCheck:SetChecked(enabled) end
	print(('|cff1784d1SmellyFarts|r debug %s'):format(debugMode and 'on' or 'off'))
end

local function UpdatePanelInfo()
	local master = tonumber(GetCVar('Sound_MasterVolume')) or 0
	local allSound = GetCVar('Sound_EnableAllSound') == '1'
	local background = GetCVar('Sound_EnableSoundWhenGameIsInBG') == '1'
	panel.info:SetText(('Sound: %s    Master volume: %d%%\nSound in background: %s'):format(
		allSound and '|cff00ff00on|r' or '|cffff0000off|r',
		math.floor(master * 100 + 0.5),
		background and '|cff00ff00on|r' or '|cffff8000off|r'))
end

local function Preview(sound)
	if panel.handle then StopSound(panel.handle) end
	local willPlay, handle = PlayEntry(sound)
	panel.handle = handle
	if willPlay then
		panel.status:SetText('|cff00ff00Playing:|r ' .. sound.name)
	else
		panel.status:SetText('|cffff0000Not played:|r ' .. sound.name .. ' (sound off, missing file or no free channel)')
	end
	UpdatePanelInfo()
end

local function CreatePanel()
	local ROW = 26
	panel = CreateFrame('Frame', 'SmellyFartsTestFrame', UIParent, 'BasicFrameTemplateWithInset')
	panel:SetSize(320, 150 + #SOUNDS * ROW)
	panel:SetPoint('CENTER')
	panel:SetFrameStrata('DIALOG')
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag('LeftButton')
	panel:SetScript('OnDragStart', panel.StartMoving)
	panel:SetScript('OnDragStop', panel.StopMovingOrSizing)
	panel:Hide()
	tinsert(UISpecialFrames, panel:GetName()) -- Escape closes it

	local title = panel.TitleText or panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	if not panel.TitleText then title:SetPoint('TOP', 0, -5) end
	title:SetText('SmellyFarts sound test')

	for i, sound in ipairs(SOUNDS) do
		local play = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
		play:SetSize(60, 22)
		play:SetPoint('TOPLEFT', 16, -34 - (i - 1) * ROW)
		play:SetText('Play')
		play:SetScript('OnClick', function() Preview(sound) end)
		local label = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
		label:SetPoint('LEFT', play, 'RIGHT', 10, 0)
		label:SetText(sound.name)
	end

	local top = -34 - #SOUNDS * ROW - 6
	local random = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
	random:SetSize(100, 22)
	random:SetPoint('TOPLEFT', 16, top)
	random:SetText('Play random')
	random:SetScript('OnClick', function() Preview(SOUNDS[math.random(#SOUNDS)]) end)

	local stop = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
	stop:SetSize(60, 22)
	stop:SetPoint('LEFT', random, 'RIGHT', 6, 0)
	stop:SetText('Stop')
	stop:SetScript('OnClick', function()
		if panel.handle then StopSound(panel.handle) end
		panel.handle = nil
		panel.status:SetText('')
	end)

	local check = CreateFrame('CheckButton', nil, panel, 'UICheckButtonTemplate')
	check:SetSize(24, 24)
	check:SetPoint('TOPLEFT', 14, top - 28)
	check:SetScript('OnClick', function(self) SetDebug(self:GetChecked() and true or false) end)
	local checkLabel = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	checkLabel:SetPoint('LEFT', check, 'RIGHT', 4, 0)
	checkLabel:SetText('Debug messages in chat')
	panel.debugCheck = check

	local status = panel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
	status:SetPoint('TOPLEFT', 18, top - 58)
	status:SetPoint('RIGHT', -18, 0)
	status:SetJustifyH('LEFT')
	panel.status = status

	local info = panel:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
	info:SetPoint('BOTTOMLEFT', 18, 12)
	info:SetJustifyH('LEFT')
	panel.info = info

	panel:SetScript('OnShow', function()
		check:SetChecked(debugMode)
		status:SetText('')
		UpdatePanelInfo()
	end)
end

local function TogglePanel()
	if not panel then CreatePanel() end
	panel:SetShown(not panel:IsShown())
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

local button

local function UpdateButton()
	if not button then return end
	button.icon:SetDesaturated(not db.enabled)
	button.icon:SetVertexColor(db.enabled and 1 or 0.5, db.enabled and 1 or 0.5, db.enabled and 1 or 0.5)
end

local function PlaceButton()
	local angle = math.rad(db.minimapAngle)
	local radius = (Minimap:GetWidth() / 2) + 10
	button:ClearAllPoints()
	button:SetPoint('CENTER', Minimap, 'CENTER', math.cos(angle) * radius, math.sin(angle) * radius)
end

local function SetEnabled(enabled)
	db.enabled = enabled
	UpdateEvents()
	UpdateButton()
	print(('|cff1784d1SmellyFarts|r %s'):format(enabled and '|cff00ff00enabled|r' or '|cffff0000disabled|r'))
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
	GameTooltip:AddLine('SmellyFarts')
	GameTooltip:AddLine(db.enabled and '|cff00ff00Enabled|r' or '|cffff0000Disabled|r')
	GameTooltip:AddLine('Left-click: enable / disable', 1, 1, 1)
	GameTooltip:AddLine('Shift + middle-click: sound test panel', 1, 1, 1)
	GameTooltip:AddLine('Drag: move', 1, 1, 1)
	GameTooltip:Show()
end

local function CreateButton()
	-- built like a LibDBIcon button (same chrome textures) so minimap button
	-- collectors such as BenisUI's pick it up
	button = CreateFrame('Button', 'SmellyFartsMinimapButton', Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata('MEDIUM')
	button:SetFrameLevel(8)
	button:RegisterForClicks('LeftButtonUp', 'MiddleButtonUp')
	button:RegisterForDrag('LeftButton')
	button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

	local overlay = button:CreateTexture(nil, 'OVERLAY')
	overlay:SetSize(53, 53)
	overlay:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
	overlay:SetPoint('TOPLEFT')

	local background = button:CreateTexture(nil, 'BACKGROUND')
	background:SetSize(20, 20)
	background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
	background:SetPoint('TOPLEFT', 7, -5)

	local icon = button:CreateTexture(nil, 'ARTWORK')
	icon:SetSize(17, 17)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint('TOPLEFT', 7, -6)
	button.icon = icon

	button:SetScript('OnClick', function(self, mouseButton)
		if mouseButton == 'MiddleButton' then
			if IsShiftKeyDown() then TogglePanel() end
		else
			SetEnabled(not db.enabled)
		end
		if GameTooltip:IsOwned(self) then ShowTooltip(self) end
	end)
	button:SetScript('OnEnter', ShowTooltip)
	button:SetScript('OnLeave', GameTooltip_Hide)

	button:SetScript('OnDragStart', function(self)
		self:SetScript('OnUpdate', function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			PlaceButton()
		end)
	end)
	button:SetScript('OnDragStop', function(self)
		self:SetScript('OnUpdate', nil)
	end)

	PlaceButton()
	UpdateButton()
end

--------------------------------------------------------------------------------
-- Events / slash
--------------------------------------------------------------------------------

events:SetScript('OnEvent', function(_, event, ...)
	if event == 'UNIT_HEALTH' or event == 'UNIT_FLAGS' then
		CheckUnit((...))
	elseif event == 'NAME_PLATE_UNIT_ADDED' or event == 'ARENA_OPPONENT_UPDATE' then
		-- a token now points at someone (maybe a corpse): record, don't play
		CheckUnit((...), true)
	elseif event == 'CHAT_MSG_COMBAT_HONOR_GAIN' then
		OnHonorGain()
	elseif event == 'PLAYER_TARGET_CHANGED' then
		CheckUnit('target', true)
	elseif event == 'PLAYER_FOCUS_CHANGED' then
		CheckUnit('focus', true)
	elseif event == 'PLAYER_ENTERING_WORLD' then
		wipe(units)
		CheckAll()
	elseif event == 'ADDON_LOADED' and ... == ADDON_NAME then
		SmellyFartsDB = SmellyFartsDB or {}
		db = SmellyFartsDB
		for key, value in pairs(defaults) do
			if db[key] == nil then db[key] = value end
		end
		CreateButton()
		UpdateEvents()
	end
end)
events:RegisterEvent('ADDON_LOADED')

SLASH_SMELLYFARTS1 = '/farts'
SLASH_SMELLYFARTS2 = '/smellyfarts'
SlashCmdList.SMELLYFARTS = function(msg)
	msg = (msg or ''):lower():match('^%s*(.-)%s*$')
	if msg == 'test' then
		PlayDeathSound()
	elseif msg == 'on' then
		SetEnabled(true)
	elseif msg == 'off' then
		SetEnabled(false)
	elseif msg == '' or msg == 'toggle' then
		SetEnabled(not db.enabled)
	elseif msg == 'sounds' then
		TogglePanel()
	elseif msg == 'debug' then
		SetDebug(not debugMode)
	else
		print('|cff1784d1SmellyFarts|r /farts [on | off | toggle | test | sounds | debug]')
	end
end
