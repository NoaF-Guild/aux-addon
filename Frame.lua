module 'aux'

local gui = require 'aux.gui'

function LOAD()
    -- SavedVariables cache becomes available only after VARIABLES_LOADED.
    -- Restore the main window position here (not at file load time).
    if AuxFrame and AuxFrame._restore_window_position then
        AuxFrame:_restore_window_position()
    end
    for _, v in ipairs(tab_info) do
        tabs:create_tab(v.name)
    end
end

do
    -- Do NOT call character_data() here: cache isn't ready during file load.
    local window_data
    local default_window = { point = 'LEFT', relative_point = 'LEFT', x = 100, y = 0 }
    local frame = CreateFrame('Frame', 'AuxFrame', UIParent)
	tinsert(UISpecialFrames, 'AuxFrame')
	gui.set_window_style(frame)
	gui.set_size(frame, 768, 447)
	frame:ClearAllPoints()
    -- Default position until cache is ready.
    frame:SetPoint(default_window.point, UIParent, default_window.relative_point, default_window.x, default_window.y)
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag('LeftButton')
	frame:SetScript('OnDragStart', function() this:StartMoving() end)
    frame:SetScript('OnDragStop', function()
		this:StopMovingOrSizing()
		local point, relative_to, relative_point, x, y = this:GetPoint(1)
        -- Store only UIParent-anchored offsets (after cache is ready).
        if window_data then
            window_data.point = point
            window_data.relative_point = relative_point
            window_data.x = x
            window_data.y = y
        end
	end)
	frame:SetScript('OnShow', function() PlaySound('AuctionWindowOpen') end)
	frame:SetScript('OnHide', function() PlaySound('AuctionWindowClose'); CloseAuctionHouse() end)
	frame.content = CreateFrame('Frame', nil, frame)
	frame.content:SetPoint('TOPLEFT', 4, -80)
	frame.content:SetPoint('BOTTOMRIGHT', -4, 35)
	frame:Hide()

    -- Restore position once SavedVariables cache is ready.
    function frame:_restore_window_position()
        if not window_data then
            window_data = character_data('window', default_window)
        end
        this:ClearAllPoints()
        this:SetPoint(window_data.point or default_window.point, UIParent, window_data.relative_point or (window_data.point or default_window.relative_point), window_data.x or default_window.x, window_data.y or default_window.y)
    end

	M.AuxFrame = frame
end
do
	tabs = gui.tabs(AuxFrame, 'DOWN')
	tabs._on_select = on_tab_click
	function M.set_tab(id) tabs:select(id) end
end
do
	local btn = gui.button(AuxFrame)
	btn:SetPoint('BOTTOMRIGHT', -5, 5)
	gui.set_size(btn, 60, 24)
	btn:SetText('Close')
	btn:SetScript('OnClick', function() AuxFrame:Hide() end)
	close_button = btn
end
do
	local btn = gui.button(AuxFrame, gui.font_size.small)
	btn:SetPoint('RIGHT', close_button, 'LEFT' , -5, 0)
	gui.set_size(btn, 60, 24)
	btn:SetText(color.blizzard'Blizzard UI')
	btn:SetScript('OnClick',function()
		if AuctionFrame:IsVisible() then HideUIPanel(AuctionFrame) else ShowUIPanel(AuctionFrame) end
	end)
	M.blizzard_ui_button = btn
end