module 'aux.core.shortcut'

include 'T'
include 'aux'

local info = require 'aux.util.info'

do
	local orig = ContainerFrameItemButton_OnClick
	_G.ContainerFrameItemButton_OnClick = vararg-function(arg)
		local self = arg[1]
		local button = arg[2]
		if button == 'RightButton' and not get_modified() and get_tab() and get_tab().name == 'Post' and AuxFrame and AuxFrame:IsShown() then
			local bag = self:GetParent():GetID()
			local slot = self:GetID()
			local item_info = info.container_item(bag, slot)
			if item_info and get_tab().USE_ITEM then
				get_tab().USE_ITEM(item_info)
				return
			end
		end
		return orig(unpack(arg))
	end
end
