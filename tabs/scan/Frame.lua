module 'aux.tabs.scan'

local gui = require 'aux.gui'

frame = CreateFrame('Frame', nil, AuxFrame)
frame:SetAllPoints()
frame:Hide()

do
    local text = frame:CreateFontString(nil, 'ARTWORK')
    gui.apply_font(text, 'text')
    text:SetJustifyH('CENTER')
    text:SetPoint('BOTTOM', AuxFrame.content, 'TOP', 0, -18)
    text:SetTextColor(color.label.enabled())
    text:SetText('Last scan: --')
    last_scan_text = text
end

do
    local btn = gui.button(frame)
    btn:SetText('Full Scan')
    btn:SetWidth(120)
    btn:SetPoint('CENTER', AuxFrame.content, 'CENTER', -80, 20)
    btn:SetScript('OnClick', function() full_scan() end)
    full_scan_button = btn
end

do
    local btn = gui.button(frame)
    btn:SetText('Fast Scan')
    btn:SetWidth(120)
    btn:SetPoint('CENTER', AuxFrame.content, 'CENTER', 80, 20)
    btn:SetScript('OnClick', function() fast_scan() end)
    fast_scan_button = btn
end

do
    local bar = gui.status_bar(frame)
    bar:SetPoint('TOPLEFT', full_scan_button, 'BOTTOMLEFT', -130, -30)
    bar:SetPoint('TOPRIGHT', fast_scan_button, 'BOTTOMRIGHT', 130, -30)
    bar:SetHeight(22)
    bar:update_status(1, 1)
    bar:set_text('')
    scan_status_bar = bar
end

do
    local text = frame:CreateFontString(nil, 'ARTWORK')
    gui.apply_font(text, 'text')
    text:SetJustifyH('CENTER')
    text:SetPoint('TOP', scan_status_bar, 'BOTTOM', 0, -8)
    text:SetTextColor(color.label.enabled())
    text:SetText('Pages scanned: 0')
    scan_pages_text = text
end

do
    local text = frame:CreateFontString(nil, 'ARTWORK')
    gui.apply_font(text, 'text')
    text:SetJustifyH('CENTER')
    text:SetPoint('TOP', scan_pages_text, 'BOTTOM', 0, -4)
    text:SetTextColor(color.label.enabled())
    text:SetText('Elapsed: --   ETA: --')
    scan_time_text = text
end

do
	local btn = gui.button(frame)
	btn:SetText('Stop scan')
	btn:SetPoint('TOP', scan_time_text, 'BOTTOM', 0, -10)
	btn:SetScript('OnClick', function() stop_scan() end)
	stop_scan_button = btn
	stop_scan_button:Hide()
end
