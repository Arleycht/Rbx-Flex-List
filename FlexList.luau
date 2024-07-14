--[[
	MIT License

	Copyright (c) 2024 Arleycht Joy (arleycht@proton.me)

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
--]]

--!strict

local ATTR_BASIS_SIZE = "FlexBasisSize"

local lastChanged = 0
local renderUpdateConnectionId: string?

local function map<A, B>(t: { A }, f: (A) -> B): { B }
	local u = {}
	for _, v in t do
		table.insert(u, f(v))
	end
	return u
end

local function fold<A, B>(t: { A }, f: (A, B) -> B, init: B): B
	local u = init
	for _, v in t do
		u = f(v, u)
	end
	return u
end

-- Merge sort because there is no native stable sort implementation
local function mergeSort<T>(t: { T }, comparator: (a: T, b: T) -> boolean): { T }
	if #t < 2 then
		return t
	elseif #t == 2 then
		local a, b = t[1], t[2]
		if comparator(a, b) then
			return { a, b }
		else
			return { b, a }
		end
	else
		local mid = math.ceil(#t / 2)
		local left = mergeSort(table.move(t, 1, mid, 1, {}), comparator)
		local right = mergeSort(table.move(t, mid + 1, #t, 1, {}), comparator)
		local result = {}
		local i, j, k = 1, 1, 1
		while i <= #left and j <= #right do
			if comparator(left[i], right[j]) then
				result[k] = left[i]
				i += 1
			else
				result[k] = right[j]
				j += 1
			end
			k += 1
		end
		while i <= #left do
			result[k] = left[i]
			i += 1
			k += 1
		end
		while j <= #right do
			result[k] = right[j]
			j += 1
			k += 1
		end
		return result
	end
end

local function getName(o)
	return o.Name
end

local function getAttributeWithDefault<T>(instance: Instance, attrName: string, default: T): T
	local value = instance:GetAttribute(attrName)
	if value == nil or typeof(value) ~= typeof(default) then
		instance:SetAttribute(attrName, default)
		return default
	else
		return value :: T
	end
end

local function snapChoice(choices: { string }, s: string?, default: string?): string?
	if default then
		assert(table.find(choices, default) ~= nil)
	end
	if not s then
		return default
	end
	for _, v in choices do
		if s:lower() == v:lower() then
			return v
		end
	end
	return default
end

local function importListConfiguration()
	local layout = script.Parent:FindFirstChildWhichIsA("UIListLayout") :: UIListLayout?

	if layout then
		-- Default features
		script:SetAttribute("FillDirection", layout.FillDirection.Name)
		script:SetAttribute("HorizontalAlignment", layout.HorizontalAlignment.Name)
		script:SetAttribute("VerticalAlignment", layout.VerticalAlignment.Name)
		script:SetAttribute("SortOrder", layout.SortOrder.Name)
		script:SetAttribute("Padding", layout.Padding)
		script:SetAttribute("Wraps", layout.Wraps)

		-- Beta features
		pcall(function()
			script:SetAttribute("VerticalFlex", layout.VerticalFlex.Name)
			script:SetAttribute("HorizontalFlex", layout.HorizontalFlex.Name)
			script:SetAttribute("ItemLineAlignment", layout.ItemLineAlignment.Name)
		end)

		layout:Destroy()
	end
end

local function getListConfiguration()
	local enumDefaults = {
		FillDirection = map(Enum.FillDirection:GetEnumItems(), getName),
		HorizontalAlignment = map(Enum.HorizontalAlignment:GetEnumItems(), getName),
		HorizontalFlex = map(Enum.UIFlexAlignment:GetEnumItems(), getName),
		ItemLineAlignment = map(Enum.ItemLineAlignment:GetEnumItems(), getName),
		SortOrder = map(Enum.SortOrder:GetEnumItems(), getName),
		VerticalAlignment = map(Enum.VerticalAlignment:GetEnumItems(), getName),
		VerticalFlex = map(Enum.UIFlexAlignment:GetEnumItems(), getName),
	} :: { [string]: { string } }

	for attrName, values in enumDefaults do
		local attrValue = script:GetAttribute(attrName)
		script:SetAttribute(attrName, snapChoice(values, attrValue, nil))
	end

	return {
		FillDirection = getAttributeWithDefault(script, "FillDirection", Enum.FillDirection.Vertical.Name),
		HorizontalAlignment = getAttributeWithDefault(
			script,
			"HorizontalAlignment",
			Enum.HorizontalAlignment.Left.Name
		),
		HorizontalFlex = getAttributeWithDefault(script, "HorizontalFlex", Enum.UIFlexAlignment.None.Name),
		ItemLineAlignment = getAttributeWithDefault(script, "ItemLineAlignment", Enum.ItemLineAlignment.Automatic.Name),
		Padding = getAttributeWithDefault(script, "Padding", UDim.new()),
		SortOrder = getAttributeWithDefault(script, "SortOrder", Enum.SortOrder.LayoutOrder.Name),
		VerticalAlignment = getAttributeWithDefault(script, "VerticalAlignment", Enum.VerticalAlignment.Top.Name),
		VerticalFlex = getAttributeWithDefault(script, "VerticalFlex", Enum.UIFlexAlignment.None.Name),
		Wraps = getAttributeWithDefault(script, "Wraps", false),
	}
end

local function getFlexConfiguration(object: GuiObject)
	local config = object:FindFirstChild("FlexConfiguration")
	local uiFlexItem = object:FindFirstChildWhichIsA("UIFlexItem")

	if uiFlexItem then
		if config then
			config:Destroy()
		end

		config = Instance.new("Configuration") :: Instance
		config.Name = "FlexConfiguration"
		config.Parent = object

		config:SetAttribute("FlexMode", uiFlexItem.FlexMode.Name)
		config:SetAttribute("GrowRatio", uiFlexItem.GrowRatio)
		config:SetAttribute("ItemLineAlignment", uiFlexItem.ItemLineAlignment.Name)
		config:SetAttribute("ShrinkRatio", uiFlexItem.ShrinkRatio)

		uiFlexItem:Destroy()
	end

	if config then
		local flexMode = getAttributeWithDefault(config, "FlexMode", Enum.UIFlexMode.None.Name)
		local growRatio = getAttributeWithDefault(config, "GrowRatio", 0)
		local itemLineAlignment =
			getAttributeWithDefault(config, "ItemLineAlignment", Enum.ItemLineAlignment.Automatic.Name)
		local shrinkRatio = getAttributeWithDefault(config, "ShrinkRatio", 0)

		-- Enforce value validity

		local uiFlexModeItems = map(Enum.UIFlexMode:GetEnumItems(), getName)
		local itemLineAlignmentItems = map(Enum.ItemLineAlignment:GetEnumItems(), getName)

		flexMode = snapChoice(uiFlexModeItems, flexMode) or Enum.UIFlexMode.None.Name
		itemLineAlignment = snapChoice(itemLineAlignmentItems, itemLineAlignment)
			or Enum.ItemLineAlignment.Automatic.Name

		growRatio = math.max(0, growRatio)
		shrinkRatio = math.max(0, shrinkRatio)

		local flexConfig = {
			FlexMode = flexMode,
			GrowRatio = growRatio,
			ItemLineAlignment = itemLineAlignment,
			ShrinkRatio = shrinkRatio,
		}

		if flexConfig.FlexMode == Enum.UIFlexMode.Fill.Name then
			flexConfig.GrowRatio = 1
			flexConfig.ShrinkRatio = 1
		elseif flexConfig.FlexMode == Enum.UIFlexMode.Grow.Name then
			flexConfig.GrowRatio = 1
			flexConfig.ShrinkRatio = 0
		elseif flexConfig.FlexMode == Enum.UIFlexMode.Shrink.Name then
			flexConfig.GrowRatio = 0
			flexConfig.ShrinkRatio = 1
		end

		return flexConfig
	end

	local config = {
		FlexMode = Enum.UIFlexMode.None.Name,
		GrowRatio = 1,
		ItemLineAlignment = Enum.ItemLineAlignment.Automatic.Name,
		ShrinkRatio = 1,
	}

	return config
end

local function udimToAbsolute(size: UDim, parentSize: number): number
	return size.Offset + (size.Scale * parentSize)
end

local function udim2ToAbsolute(size: UDim2, parentSize: Vector2): Vector2
	return Vector2.new(udimToAbsolute(size.X, parentSize.X), udimToAbsolute(size.Y, parentSize.Y))
end

local function getBasisSize(object: GuiObject): UDim2
	if not object:GetAttribute(ATTR_BASIS_SIZE) then
		object:SetAttribute(ATTR_BASIS_SIZE, object.Size)
	end
	return object:GetAttribute(ATTR_BASIS_SIZE)
end

local function roundAllocations(values: { number }, target: number): { number }
	local totalError = target
	local reallocated = {}

	for i, v in values do
		local roundedValue = math.floor(v)
		totalError -= roundedValue
		table.insert(reallocated, {
			index = i,
			value = roundedValue,
			error = v - roundedValue,
		})
	end

	mergeSort(reallocated, function(a, b)
		return a.error > b.error
	end)

	local result = {}

	for _, entry in reallocated do
		if totalError >= 1 then
			entry.value += 1
			totalError -= 1
		end
		result[entry.index] = entry.value
	end

	return result
end

local function calculateFlex(values: { number }, ratios: { Vector2 }, target: number)
	local available = target - fold(values, function(a, b)
		return a + b
	end, 0)
	local totalRatio = fold(ratios, function(a, b)
		return a + b
	end, Vector2.zero)

	local newValues = {}

	if available > 0 then
		for i, v in values do
			local ratio = ratios[i].X / totalRatio.X

			-- If the total ratio is 0
			if ratio ~= ratio then
				ratio = 1 / #values
			end

			newValues[i] = v + (available * ratio)
		end
	else
		local divisor = 0

		for i, v in values do
			newValues[i] = v * ratios[i].Y

			if newValues[i] == 0 then
				newValues[i] = v
			end

			divisor += newValues[i]
		end

		for i = 1, #newValues do
			local ratio = newValues[i] / divisor
			newValues[i] = values[i] + (available * ratio)
		end
	end

	return roundAllocations(newValues, target)
end

local function update()
	local parent = script.Parent :: GuiObject
	local listConfig = getListConfiguration()
	local isVertical = (listConfig.FillDirection == Enum.FillDirection.Vertical.Name)
	local flex = listConfig.VerticalFlex
	local crossFlex = listConfig.HorizontalFlex
	local verticalAlignment = listConfig.VerticalAlignment
	local horizontalAlignment = listConfig.HorizontalAlignment

	local ALIGNMENT_MAPPING = {
		Top = "Start",
		Left = "Start",
		Bottom = "End",
		Right = "End",
		Center = "Center",
	}

	verticalAlignment = ALIGNMENT_MAPPING[verticalAlignment]
	horizontalAlignment = ALIGNMENT_MAPPING[horizontalAlignment]

	local totalSpace = parent.AbsoluteSize
	local fixedPadding = Vector2.new()

	local guiObjects = {}
	-- Because absolute sizes will differ on XY axes when using
	-- relative scale values in UDim2, we cache the true absolute
	-- sizes so that when they are temporarily flipped, we still
	-- use the correct values that will be rendered.
	local guiObjectSizes = {}
	local flexConfigs = {}

	for _, object in parent:GetChildren() do
		if object:IsA("GuiObject") and object.Visible then
			object.Size = getBasisSize(object)
			flexConfigs[object] = getFlexConfiguration(object)
			guiObjectSizes[object] = object.AbsoluteSize
			table.insert(guiObjects, object)
		elseif object:IsA("UIPadding") then
			fixedPadding += udim2ToAbsolute(
				UDim2.new(object.PaddingLeft + object.PaddingRight, object.PaddingTop + object.PaddingBottom),
				totalSpace
			)
		end
	end

	-- Flip XY to exploit symmetry

	if not isVertical then
		flex, crossFlex = crossFlex, flex
		verticalAlignment, horizontalAlignment = horizontalAlignment, verticalAlignment

		totalSpace = Vector2.new(totalSpace.Y, totalSpace.X)
		fixedPadding = Vector2.new(fixedPadding.Y, fixedPadding.X)

		for _, object in guiObjects do
			object.Position = UDim2.new(object.Position.Y, object.Position.X)
			object.Size = UDim2.new(object.Size.Y, object.Size.X)
			guiObjectSizes[object] = Vector2.new(guiObjectSizes[object].Y, guiObjectSizes[object].X)
		end
	end

	-- Apply list sort order

	guiObjects = mergeSort(guiObjects, function(a: GuiObject, b: GuiObject)
		if listConfig.SortOrder == Enum.SortOrder.Name.Name then
			return a.Name < b.Name
		else
			return a.LayoutOrder < b.LayoutOrder
		end
	end)

	-- Flex

	local listPadding = listConfig.Padding.Offset + (listConfig.Padding.Scale * totalSpace.Y)
	local availableSpace = totalSpace - fixedPadding
	local flexRows = {}
	local flexRowWidths = {}

	-- Calculate wrapping

	do
		local flexRow = {}
		local maxWidth = 0
		local currentY = 0

		for i = 1, #guiObjects do
			local object = guiObjects[i]
			local size = guiObjectSizes[object]

			if listConfig.Wraps and currentY + size.Y > availableSpace.Y and #flexRow > 0 then
				table.insert(flexRows, flexRow)
				table.insert(flexRowWidths, maxWidth)

				flexRow = {}
				maxWidth = 0
				currentY = 0
			end

			table.insert(flexRow, object)

			maxWidth = math.max(maxWidth, size.X)
			currentY += size.Y + listPadding
		end

		if #flexRow > 0 then
			table.insert(flexRows, flexRow)
			table.insert(flexRowWidths, maxWidth)
		end
	end

	-- List layout

	local currentX = 0
	local rowPadding = listPadding
	local useCrossAlignment = false

	if crossFlex ~= Enum.UIFlexAlignment.Fill.Name then
		local emptyRowSpace = availableSpace.X

		for _, width in flexRowWidths do
			emptyRowSpace -= width
		end

		if crossFlex == Enum.UIFlexAlignment.SpaceAround.Name then
			rowPadding = emptyRowSpace / #flexRows
			currentX = rowPadding / 2
		elseif crossFlex == Enum.UIFlexAlignment.SpaceBetween.Name then
			rowPadding = emptyRowSpace / (#flexRows - 1)
		elseif crossFlex == Enum.UIFlexAlignment.SpaceEvenly.Name then
			rowPadding = emptyRowSpace / (#flexRows + 1)
			currentX = rowPadding
		elseif crossFlex == Enum.UIFlexAlignment.None.Name then
			useCrossAlignment = true
		end
	end

	-- Cross flex

	if listConfig.ItemLineAlignment == Enum.ItemLineAlignment.Automatic.Name then
		if crossFlex == Enum.UIFlexMode.Fill.Name then
			listConfig.ItemLineAlignment = Enum.ItemLineAlignment.Stretch.Name
		elseif flex ~= Enum.UIFlexAlignment.None.Name then
			useCrossAlignment = true
		end
	end

	if crossFlex == Enum.UIFlexMode.Fill.Name then
		if listConfig.ItemLineAlignment == Enum.ItemLineAlignment.Stretch.Name then
			local ratios = {}

			for i, flexRow in flexRows do
				ratios[i] = Vector2.one
			end

			local sizes = flexRowWidths
			local target = availableSpace.X - (rowPadding * (#sizes - 1))
			local newSizes = calculateFlex(sizes, ratios, target)

			for i, flexRow in flexRows do
				for _, object in flexRow do
					object.Size = UDim2.new(UDim.new(0, newSizes[i]), object.Size.Y)
					guiObjectSizes[object] = Vector2.new(newSizes[i], guiObjectSizes[object].Y)
				end
			end
		else
			-- Override cross alignment to reuse code
			horizontalAlignment = listConfig.ItemLineAlignment
			useCrossAlignment = true
		end
	end

	-- Use cross alignment when flex is disabled

	if useCrossAlignment then
		if horizontalAlignment ~= "Start" then
			currentX = availableSpace.X

			for _, width in flexRowWidths do
				currentX -= width
			end

			if horizontalAlignment == "Center" then
				currentX /= 2
			end
		end
	end

	-- Normal flex

	if flex == Enum.UIFlexMode.Fill.Name then
		for i, flexRow in flexRows do
			local target = availableSpace.Y - (listPadding * (#flexRow - 1))
			local sizes = {}
			local ratios = {}
			local totalRatios = Vector2.zero

			for j, object in flexRow do
				sizes[j] = guiObjectSizes[object].Y
				ratios[j] = Vector2.new(flexConfigs[object].GrowRatio, flexConfigs[object].ShrinkRatio)

				totalRatios += ratios[j]
			end

			local newSizes = calculateFlex(sizes, ratios, target)

			for j, object in flexRow do
				object.Size = UDim2.new(object.Size.X, UDim.new(0, newSizes[j]))
				guiObjectSizes[object] = Vector2.new(guiObjectSizes[object].X, newSizes[j])
			end
		end
	end

	-- Apply aspect ratio constraints

	for _, object in guiObjects do
		local constraint = object:FindFirstChildWhichIsA("UIAspectRatioConstraint")

		if constraint then
			local parentSize = availableSpace
			local size = guiObjectSizes[object]

			if not isVertical then
				parentSize = Vector2.new(parentSize.Y, parentSize.X)
				size = Vector2.new(size.Y, size.X)
			end

			if constraint.DominantAxis == Enum.DominantAxis.Width then
				size = Vector2.new(size.X, size.X / constraint.AspectRatio)
			else
				size = Vector2.new(size.Y * constraint.AspectRatio, 0)
			end

			if constraint.AspectType == Enum.AspectType.ScaleWithParentSize then
				local ratio = parentSize / size
				size *= math.min(ratio.X, ratio.Y)
			end

			if not isVertical then
				guiObjectSizes[object] = Vector2.new(size.Y, size.X)
			else
				guiObjectSizes[object] = size
			end
		end
	end

	for i, flexRow in flexRows do
		local maxWidth = 0
		local currentY = 0
		local columnPadding = listPadding
		local emptyColumnSpace = availableSpace.Y

		for _, object in flexRow do
			emptyColumnSpace -= guiObjectSizes[object].Y
		end

		if flex == Enum.UIFlexAlignment.SpaceAround.Name then
			columnPadding = emptyColumnSpace / #flexRow
			currentY = columnPadding / 2
		elseif flex == Enum.UIFlexAlignment.SpaceBetween.Name then
			columnPadding = emptyColumnSpace / (#flexRow - 1)
		elseif flex == Enum.UIFlexAlignment.SpaceEvenly.Name then
			columnPadding = emptyColumnSpace / (#flexRow + 1)
			currentY = columnPadding
		elseif flex == Enum.UIFlexAlignment.None.Name then
			emptyColumnSpace -= columnPadding * (#flexRow - 1)
			currentY = emptyColumnSpace

			if verticalAlignment == "Center" then
				currentY /= 2
			elseif verticalAlignment == "Start" then
				currentY = 0
			end
		end

		for _, object in flexRow do
			object.Position = UDim2.fromOffset(currentX, currentY)
			currentY += guiObjectSizes[object].Y + columnPadding

			if useCrossAlignment and horizontalAlignment ~= "Start" then
				local width = flexRowWidths[i]
				local objectWidth = guiObjectSizes[object].X
				local offset = width - objectWidth

				if horizontalAlignment == "Center" then
					offset /= 2
				end

				object.Position += UDim2.fromOffset(offset, 0)
			end

			maxWidth = math.max(maxWidth, guiObjectSizes[object].X)
		end

		currentX += maxWidth + rowPadding
	end

	-- Flip XY again to restore actual values

	if not isVertical then
		for _, object in guiObjects do
			object.Position = UDim2.new(object.Position.Y, object.Position.X)
			object.Size = UDim2.new(object.Size.Y, object.Size.X)
		end
	end

	if renderUpdateConnectionId and time() - lastChanged > 0.5 then
		game:GetService("RunService"):UnbindFromRenderStep(renderUpdateConnectionId)
		renderUpdateConnectionId = nil
	end
end

local function onChanged()
	if not renderUpdateConnectionId then
		if time() - lastChanged < 0.5 then
			renderUpdateConnectionId = game:GetService("HttpService"):GenerateGUID()
			game:GetService("RunService")
				:BindToRenderStep(renderUpdateConnectionId, Enum.RenderPriority.Camera.Value - 1, update)
		else
			update()
		end
	end
	lastChanged = time()
end

local function init()
	importListConfiguration()

	local parent = script.Parent
	local connections = {}

	local function onChildAdded(child)
		if child:IsA("GuiObject") then
			connections[child] = {
				child.Changed:Connect(onChanged),
				child.AttributeChanged:Connect(onChanged),
			}
		end
		onChanged()
	end

	local function onChildRemoved(child)
		for otherChild, childConnections in connections do
			if otherChild == child or not parent:IsAncestorOf(otherChild) then
				for _, v in childConnections do
					v:Disconnect()
				end
				connections[otherChild] = nil
			end
		end
		onChanged()
	end

	script.Changed:Connect(onChanged)
	script.AttributeChanged:Connect(onChanged)
	parent.Changed:Connect(onChanged)
	parent.AttributeChanged:Connect(onChanged)
	parent.ChildAdded:Connect(onChildAdded)
	parent.ChildRemoved:Connect(onChildRemoved)

	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			onChildAdded(child)
		end
	end
end

init()
