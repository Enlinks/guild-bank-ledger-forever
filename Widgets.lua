-- Navy window pieces. No Ace widgets, so the frame can stay white-on-navy.

GBLF = GBLF or {}
GBLF.Widgets = {}

local Widgets = GBLF.Widgets

GBLF.Theme = {
	bg = { 0.045, 0.075, 0.145, 0.88 },
	inset = { 0.055, 0.09, 0.16, 0.84 },
	border = { 0.82, 0.89, 0.98, 0.95 },
	borderDim = { 0.38, 0.48, 0.64, 0.9 },
	text = { 0.94, 0.96, 0.99 },
	muted = { 0.64, 0.72, 0.84 },
	row = { 0.07, 0.11, 0.20, 0.50 },
	rowAlt = { 0.035, 0.06, 0.12, 0.28 },
	rowHot = { 0.15, 0.24, 0.40, 0.78 },
	rowOn = { 0.22, 0.34, 0.54, 0.90 },
	button = { 0.10, 0.16, 0.30, 0.94 },
	buttonHot = { 0.18, 0.28, 0.46, 0.96 },
}

local Theme = GBLF.Theme

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function paint(frame, bg, border)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	local edge = border or Theme.border
	frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

function Widgets.Paint(frame, kind)
	if kind == "inset" then
		paint(frame, Theme.inset, Theme.borderDim)
	elseif kind == "hot" then
		paint(frame, Theme.buttonHot, Theme.border)
	elseif kind == "button" then
		paint(frame, Theme.button, Theme.borderDim)
	else
		paint(frame, Theme.bg, Theme.border)
	end
end

local function solid(texture, color)
	texture:SetTexture("Interface\\Buttons\\WHITE8X8")
	texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

function Widgets.Label(parent, size, color)
	local font = "GameFontHighlightSmall"
	if size == "title" then
		font = "GameFontNormalLarge"
	elseif size == "body" then
		font = "GameFontHighlight"
	end
	local text = parent:CreateFontString(nil, "OVERLAY", font)
	local tint = color or Theme.text
	text:SetTextColor(tint[1], tint[2], tint[3])
	text:SetJustifyH("LEFT")
	text:SetJustifyV("MIDDLE")
	return text
end

function Widgets.Button(parent, label, width, height)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width, height)
	Widgets.Paint(button, "button")
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	text:SetTextColor(Theme.text[1], Theme.text[2], Theme.text[3])
	text:SetText(label)
	button.label = text
	button.enabled = true
	function button:SetText(value)
		text:SetText(value)
	end
	function button:SetEnabled(on)
		self.enabled = on and true or false
		self:SetAlpha(self.enabled and 1 or 0.4)
	end
	button:SetScript("OnEnter", function(self)
		if self.enabled then
			Widgets.Paint(self, "hot")
		end
	end)
	button:SetScript("OnLeave", function(self)
		Widgets.Paint(self, self.active and "hot" or "button")
	end)
	button:SetScript("OnClick", function(self)
		if self.enabled and self.onClick then
			self.onClick()
		end
	end)
	return button
end

function Widgets.SetActive(button, active)
	button.active = active and true or false
	Widgets.Paint(button, button.active and "hot" or "button")
end

function Widgets.Check(parent, labelText)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(16, 16)
	Widgets.Paint(button, "inset")
	local mark = button:CreateTexture(nil, "OVERLAY")
	mark:SetPoint("TOPLEFT", 3, -3)
	mark:SetPoint("BOTTOMRIGHT", -3, 3)
	solid(mark, Theme.text)
	mark:Hide()
	button.mark = mark
	button.checked = false
	function button:SetChecked(on)
		self.checked = on and true or false
		if self.checked then
			mark:Show()
		else
			mark:Hide()
		end
	end
	function button:GetChecked()
		return self.checked
	end
	button:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		if self.onClick then
			self.onClick(self.checked)
		end
	end)
	local label = Widgets.Label(parent, "small", Theme.text)
	label:SetText(labelText)
	button.label = label
	return button
end

function Widgets.Edit(parent, width, height)
	local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	box:SetSize(width, height)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	box:SetTextColor(Theme.text[1], Theme.text[2], Theme.text[3])
	box:SetTextInsets(6, 6, 0, 0)
	box:SetJustifyH("LEFT")
	Widgets.Paint(box, "inset")
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if self.onCommit then
			self.onCommit(self:GetText() or "")
		end
	end)
	box:SetScript("OnEditFocusLost", function(self)
		Widgets.Paint(self, "inset")
		if self.onCommit then
			self.onCommit(self:GetText() or "")
		end
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
	end)
	return box
end

local menu

function Widgets.CloseMenu()
	if menu then
		menu:Hide()
	end
end

function Widgets.OpenMenu(anchor, choices, onPick)
	if not menu then
		menu = CreateFrame("Frame", "GBLFDropMenu", UIParent, "BackdropTemplate")
		menu:SetFrameStrata("TOOLTIP")
		menu:SetClampedToScreen(true)
		Widgets.Paint(menu, "window")
		menu.buttons = {}
		menu:SetScript("OnHide", function(self)
			self.anchor = nil
		end)
	end
	if menu:IsShown() and menu.anchor == anchor then
		menu:Hide()
		return
	end
	local pool = menu.buttons
	local width = 140
	for index, choice in ipairs(choices) do
		local button = pool[index]
		if not button then
			button = CreateFrame("Button", nil, menu)
			button:SetHeight(20)
			local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			text:SetPoint("LEFT", 8, 0)
			text:SetPoint("RIGHT", -8, 0)
			text:SetJustifyH("LEFT")
			text:SetTextColor(Theme.text[1], Theme.text[2], Theme.text[3])
			button.label = text
			local bg = button:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			button.bg = bg
			button:SetScript("OnEnter", function(self)
				solid(self.bg, Theme.rowOn)
			end)
			button:SetScript("OnLeave", function(self)
				self.bg:SetTexture(nil)
			end)
			pool[index] = button
		end
		local pickedValue = choice.value
		local pickedText = choice.text
		button:SetScript("OnClick", function()
			menu:Hide()
			if onPick then
				onPick(pickedValue, pickedText)
			end
		end)
		button.label:SetText(pickedText)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 2, -2 - (index - 1) * 20)
		button:SetPoint("TOPRIGHT", -2, -2 - (index - 1) * 20)
		button:Show()
		local textWidth = button.label:GetStringWidth() or 0
		local guess = (string.len(pickedText) * 7) + 24
		if textWidth + 24 > guess then
			guess = textWidth + 24
		end
		if guess > width then
			width = guess
		end
	end
	for index = #choices + 1, #pool do
		pool[index]:Hide()
	end
	menu:SetSize(width, 4 + #choices * 20)
	menu.anchor = anchor
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	menu:Show()
end

function Widgets.List(parent, width, height, columns)
	local rowHeight = 20
	local headerHeight = 22
	local gutter = 14
	local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	holder:SetSize(width, height)
	Widgets.Paint(holder, "inset")

	local headers = {}
	local headerRow = CreateFrame("Frame", nil, holder)
	headerRow:SetPoint("TOPLEFT", 1, -1)
	headerRow:SetPoint("TOPRIGHT", -(gutter + 2), -1)
	headerRow:SetHeight(headerHeight)

	local list = {
		frame = holder,
		columns = columns,
		headers = headers,
		items = {},
		top = 0,
		rowHeight = rowHeight,
		onClick = nil,
		onHeader = nil,
		isSelected = nil,
	}

	local function columnWidth(column, total)
		if column.flex then
			local used = 0
			for _, other in ipairs(columns) do
				if not other.flex then
					used = used + other.width
				end
			end
			local flex = total - used
			if flex < 48 then
				flex = 48
			end
			return flex
		end
		return column.width
	end

	local function placeHeaders()
		local total = headerRow:GetWidth()
		if total < 20 then
			total = width - gutter - 4
		end
		local x = 0
		for index, column in ipairs(columns) do
			local columnSize = columnWidth(column, total)
			column.drawWidth = columnSize
			local button = headers[index]
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", headerRow, "TOPLEFT", x, 0)
			button:SetSize(columnSize, headerHeight)
			x = x + columnSize
		end
	end

	for index, column in ipairs(columns) do
		local button = CreateFrame("Button", nil, headerRow)
		local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("LEFT", 4, 0)
		text:SetPoint("RIGHT", -2, 0)
		text:SetJustifyH(column.align or "LEFT")
		text:SetTextColor(Theme.muted[1], Theme.muted[2], Theme.muted[3])
		text:SetText(column.text)
		button.label = text
		local headerKey = column.key
		button:SetScript("OnClick", function()
			if list.onHeader then
				list.onHeader(headerKey)
			end
		end)
		headers[index] = button
	end

	local rowsFrame = CreateFrame("Frame", nil, holder)
	rowsFrame:SetPoint("TOPLEFT", 1, -(headerHeight + 1))
	rowsFrame:SetPoint("BOTTOMRIGHT", -(gutter + 2), 2)
	list.rowsFrame = rowsFrame

	local slider = CreateFrame("Slider", nil, holder, "BackdropTemplate")
	slider:SetPoint("TOPRIGHT", -2, -(headerHeight + 2))
	slider:SetPoint("BOTTOMRIGHT", -2, 2)
	slider:SetWidth(gutter - 2)
	slider:SetOrientation("VERTICAL")
	slider:SetMinMaxValues(0, 0)
	slider:SetValue(0)
	slider:SetValueStep(1)
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end
	Widgets.Paint(slider, "inset")
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
	thumb:SetVertexColor(Theme.border[1], Theme.border[2], Theme.border[3], 0.9)
	thumb:SetSize(gutter - 4, 28)
	slider:SetThumbTexture(thumb)
	list.slider = slider

	local rows = {}
	local pool = math.max(8, math.floor((height - headerHeight) / rowHeight) + 1)
	for index = 1, pool do
		local row = CreateFrame("Button", nil, rowsFrame)
		row:SetHeight(rowHeight)
		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		row.bg = bg
		row.fonts = {}
		row:SetScript("OnClick", function(self)
			if self.item and list.onClick then
				list.onClick(self.item)
			end
		end)
		row:SetScript("OnEnter", function(self)
			if not self.item then
				return
			end
			if not (list.isSelected and list.isSelected(self.item)) then
				solid(self.bg, Theme.rowHot)
			end
			if self.item.itemID and GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if GameTooltip.SetItemByID then
					GameTooltip:SetItemByID(self.item.itemID)
				else
					GameTooltip:SetHyperlink("item:" .. self.item.itemID)
				end
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function(self)
			if GameTooltip then
				GameTooltip:Hide()
			end
			list:Paint()
		end)
		rows[index] = row
	end
	list.rows = rows

	local painting = false

	local function visibleCount()
		local rowsHeight = rowsFrame:GetHeight()
		if rowsHeight < rowHeight then
			rowsHeight = height - headerHeight - 4
		end
		local count = math.floor(rowsHeight / rowHeight)
		if count < 1 then
			count = 1
		end
		if count > #rows then
			count = #rows
		end
		return count
	end

	local function cellText(item, column)
		if list.text then
			return list.text(item, column)
		end
		local value = item[column.key]
		if column.money then
			return GBLF.FormatMoneyCompact(value or 0)
		end
		if value == nil then
			return ""
		end
		return tostring(value)
	end

	function list:Paint()
		if painting then
			return
		end
		painting = true
		placeHeaders()
		local total = headerRow:GetWidth()
		if total < 20 then
			total = width - gutter - 4
		end
		local count = visibleCount()
		local maxTop = #self.items - count
		if maxTop < 0 then
			maxTop = 0
		end
		if self.top > maxTop then
			self.top = maxTop
		end
		if self.top < 0 then
			self.top = 0
		end
		slider:SetMinMaxValues(0, maxTop)
		slider:SetValue(self.top)
		if maxTop == 0 then
			slider:Hide()
		else
			slider:Show()
		end
		for index, row in ipairs(rows) do
			local item = nil
			if index <= count then
				item = self.items[self.top + index]
			end
			row.item = item
			if item then
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", rowsFrame, "TOPLEFT", 0, -((index - 1) * rowHeight))
				row:SetPoint("TOPRIGHT", rowsFrame, "TOPRIGHT", 0, -((index - 1) * rowHeight))
				local selected = self.isSelected and self.isSelected(item)
				if selected then
					solid(row.bg, Theme.rowOn)
				elseif (self.top + index) % 2 == 0 then
					solid(row.bg, Theme.row)
				else
					solid(row.bg, Theme.rowAlt)
				end
				local x = 0
				for columnIndex, column in ipairs(columns) do
					local font = row.fonts[columnIndex]
					if not font then
						font = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
						font:SetTextColor(Theme.text[1], Theme.text[2], Theme.text[3])
						if font.SetWordWrap then
							font:SetWordWrap(false)
						end
						row.fonts[columnIndex] = font
					end
					local columnSize = column.drawWidth or column.width
					font:ClearAllPoints()
					font:SetPoint("LEFT", row, "LEFT", x + 4, 0)
					font:SetWidth(math.max(8, columnSize - 6))
					font:SetJustifyH(column.align or "LEFT")
					font:SetText(cellText(item, column))
					x = x + columnSize
				end
				row:Show()
			else
				row:Hide()
			end
		end
		painting = false
	end

	slider:SetScript("OnValueChanged", function(_, value)
		local nextTop = math.floor(value + 0.5)
		if nextTop ~= list.top then
			list.top = nextTop
			list:Paint()
		end
	end)

	holder:EnableMouseWheel(true)
	holder:SetScript("OnMouseWheel", function(_, delta)
		local maxValue = select(2, slider:GetMinMaxValues())
		local nextTop = list.top - delta
		if nextTop < 0 then
			nextTop = 0
		end
		if nextTop > maxValue then
			nextTop = maxValue
		end
		list.top = nextTop
		list:Paint()
	end)

	function list:SetItems(items)
		self.items = items or {}
		self:Paint()
	end

	function list:ScrollToTop()
		self.top = 0
		self:Paint()
	end

	function list:SetMark(key, descending)
		for index, column in ipairs(columns) do
			local suffix = ""
			if column.key == key then
				suffix = descending and " v" or " ^"
			end
			headers[index].label:SetText(column.text .. suffix)
		end
	end

	holder:SetScript("OnShow", function()
		list:Paint()
	end)
	list:SetMark(nil, false)
	return list
end
