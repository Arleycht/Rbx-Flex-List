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
	local layout = script.Parent:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		script:SetAttribute("FillDirection", layout.FillDirection.Name)
		script:SetAttribute("HorizontalAlignment", layout.HorizontalAlignment.Name)
		script:SetAttribute("VerticalAlignment", layout.VerticalAlignment.Name)
		script:SetAttribute("SortOrder", layout.SortOrder.Name)
		script:SetAttribute("Padding", layout.Padding)
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

	if config then
		local flexMode = getAttributeWithDefault(config, "FlexMode", Enum.UIFlexMode.None.Name)
		local growRatio = getAttributeWithDefault(config, "GrowRatio", 0)
		local itemLineAlignment =
			getAttributeWithDefault(config, "ItemLineAlignment", Enum.ItemLineAlignment.Automatic.Name)
		local shrinkRatio = getAttributeWithDefault(config, "ShrinkRatio", 0)

		-- Enforce value validity

		local uiFlexModeItems = map(Enum.UIFlexMode:GetEnumItems(), getName)
		local itemLineAlignmentItems = map(Enum.ItemLineAlignment:GetEnumItems(), getName)

		if not table.find(uiFlexModeItems, flexMode) then
			flexMode = Enum.UIFlexMode.None.Name
		end

		if not table.find(itemLineAlignmentItems, itemLineAlignment) then
			itemLineAlignment = Enum.ItemLineAlignment.Automatic.Name
		end

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

		return flexConfig :: typeof(flexConfig)?
	end

	return nil
end

local function getBasisSize(object: GuiObject): UDim2
	if not object:GetAttribute(ATTR_BASIS_SIZE) then
		object:SetAttribute(ATTR_BASIS_SIZE, object.Size)
	end
	return object:GetAttribute(ATTR_BASIS_SIZE)
end

local function udimToAbsolute(size: UDim, parentSize: number): number
	return size.Offset + (size.Scale * parentSize)
end

local function udim2ToAbsolute(size: UDim2, parentSize: Vector2): Vector2
	return Vector2.new(udimToAbsolute(size.X, parentSize.X), udimToAbsolute(size.Y, parentSize.Y))
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

local function roundAllocations(values: { number }, target: number): { number }
	local totalError = target
	local newValues = {}
	for i, v in values do
		local roundedDelta = math.floor(v)
		totalError -= roundedDelta
		table.insert(newValues, {
			index = i,
			delta = roundedDelta,
			error = v - roundedDelta,
		})
	end

	mergeSort(newValues, function(a, b)
		return a.error > b.error
	end)

	local result = {}
	for _, entry in newValues do
		if totalError >= 1 then
			entry.delta += 1
			totalError -= 1
		end
		result[entry.index] = entry.delta
	end

	return result
end

local function update()
	local parent = script.Parent
	local listConfig = getListConfiguration()
	local isVertical = (listConfig.FillDirection == Enum.FillDirection.Vertical.Name)
	local flexAlignment = listConfig.VerticalFlex
	local crossFlexAlignment = listConfig.HorizontalFlex

	if not isVertical then
		flexAlignment, crossFlexAlignment = crossFlexAlignment, flexAlignment
	end

	local isFlex = (flexAlignment == Enum.UIFlexAlignment.Fill.Name)
	local totalSpace = math.round(isVertical and parent.AbsoluteSize.Y or parent.AbsoluteSize.X)
	local totalChildrenSpace = 0
	local totalRatio = Vector2.zero
	local guiObjects = {}
	local flexObjects = {}
	local flexConfigs = {}

	-- Load configs and calculate sums

	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(guiObjects, child)

			local basis = getBasisSize(child)
			totalChildrenSpace += udimToAbsolute(isVertical and basis.Y or basis.X, totalSpace)

			local config = getFlexConfiguration(child)

			if config then
				totalRatio += Vector2.new(config.GrowRatio, config.ShrinkRatio)
				flexConfigs[child] = config
				table.insert(flexObjects, child)
			end
		elseif child:IsA("UIPadding") then
			if isVertical then
				totalChildrenSpace += udimToAbsolute(child.PaddingTop + child.PaddingBottom, totalSpace)
			else
				totalChildrenSpace += udimToAbsolute(child.PaddingLeft + child.PaddingRight, totalSpace)
			end
		end
	end

	-- Apply list sort order

	local sortComparator = function(a: GuiObject, b: GuiObject)
		return a.LayoutOrder < b.LayoutOrder
	end

	if listConfig.SortOrder == Enum.SortOrder.LayoutOrder.Name then
		local comparator = function(a: GuiObject, b: GuiObject)
			return a.Name < b.Name
		end
	end

	guiObjects = mergeSort(guiObjects, sortComparator)
	flexObjects = mergeSort(flexObjects, sortComparator)

	local availableSpace = totalSpace - totalChildrenSpace
	local paddingPerChild = listConfig.Padding.Offset + (listConfig.Padding.Scale * totalSpace)
	local listPadding = paddingPerChild * (#guiObjects - 1)

	-- Flex

	if isFlex then
		-- Subtract list padding
		availableSpace -= listPadding

		if (availableSpace > 0 and totalRatio.X == 0) or (availableSpace < 0 and totalRatio.Y == 0) then
			isFlex = false
		else
			-- Round size deltas to nearest integer value while conserving the desired total
			local deltas = {}
			for _, object in flexObjects do
				local config = flexConfigs[object]

				if availableSpace > 0 then
					table.insert(deltas, availableSpace * config.GrowRatio / totalRatio.X)
				else
					table.insert(deltas, availableSpace * config.ShrinkRatio / totalRatio.Y)
				end
			end
			deltas = roundAllocations(deltas, availableSpace)

			-- Apply size deltas
			for i, object in flexObjects do
				local config = flexConfigs[object]
				local basis = getBasisSize(object)
				local delta = deltas[i]

				local x = basis.X
				local y = basis.Y

				if isVertical then
					y = UDim.new(basis.Y.Scale, basis.Y.Offset + delta)
				else
					x = UDim.new(basis.X.Scale, basis.X.Offset + delta)
				end

				object.Size = UDim2.new(x, y)
			end
		end
	end

	if not isFlex then
		for _, object in flexObjects do
			object.Size = getBasisSize(object)
		end
	end

	-- List layout

	local currentPosition = 0

	if flexAlignment == Enum.UIFlexAlignment.SpaceAround.Name then
		paddingPerChild = availableSpace / #guiObjects
		currentPosition = paddingPerChild / 2
	elseif flexAlignment == Enum.UIFlexAlignment.SpaceBetween.Name then
		paddingPerChild = availableSpace / (#guiObjects - 1)
	elseif flexAlignment == Enum.UIFlexAlignment.SpaceEvenly.Name then
		paddingPerChild = availableSpace / (#guiObjects + 1)
		currentPosition = paddingPerChild
	end

	for _, object in guiObjects do
		local position = UDim2.new()
		local size = 0

		-- Cross flex alignment
		if crossFlexAlignment == Enum.UIFlexAlignment.Fill.Name then
			if isVertical then
				object.Size = UDim2.new(UDim.new(1, 0), object.Size.Y)
			else
				object.Size = UDim2.new(object.Size.X, UDim.new(1, 0))
			end
		else
			if isVertical then
				object.Size = UDim2.new(getBasisSize(object).X, object.size.Y)
			else
				object.Size = UDim2.new(object.Size.X, getBasisSize(object).Y)
			end
		end

		if isVertical then
			size = object.AbsoluteSize.Y
			position = UDim2.fromOffset(0, currentPosition)

			if isFlex then
				local alignment = listConfig.ItemLineAlignment

				if flexConfigs[object] then
					alignment = flexConfigs[object].ItemLineAlignment
				end

				if alignment == Enum.ItemLineAlignment.Start.Name then
					-- Nothing to do because the default is left aligned
				elseif alignment == Enum.ItemLineAlignment.Center.Name then
					position += UDim2.fromOffset((parent.AbsoluteSize.X - object.AbsoluteSize.X) / 2, 0)
				elseif alignment == Enum.ItemLineAlignment.End.Name then
					position += UDim2.fromOffset(parent.AbsoluteSize.X - object.AbsoluteSize.X, 0)
				elseif alignment == Enum.ItemLineAlignment.Stretch.Name then
					object.Size = UDim2.new(UDim.new(1, 0), object.Size.Y)
				end
			else
				local alignment = listConfig.HorizontalAlignment

				if alignment == Enum.HorizontalAlignment.Right.Name then
					position += UDim2.fromOffset(parent.AbsoluteSize.X - object.AbsoluteSize.X, 0)
				elseif alignment == Enum.HorizontalAlignment.Center.Name then
					position += UDim2.fromOffset((parent.AbsoluteSize.X - object.AbsoluteSize.X) / 2, 0)
				end
			end
		else
			size = object.AbsoluteSize.X
			position = UDim2.fromOffset(currentPosition, 0)

			if isFlex then
				local alignment = listConfig.ItemLineAlignment

				if flexConfigs[object] then
					alignment = flexConfigs[object].ItemLineAlignment
				end

				if alignment == Enum.ItemLineAlignment.Start.Name then
					-- Nothing to do because the default is left aligned
				elseif alignment == Enum.ItemLineAlignment.Center.Name then
					position += UDim2.fromOffset(0, (parent.AbsoluteSize.Y - object.AbsoluteSize.Y) / 2)
				elseif alignment == Enum.ItemLineAlignment.End.Name then
					position += UDim2.fromOffset(0, parent.AbsoluteSize.Y - object.AbsoluteSize.Y)
				elseif alignment == Enum.ItemLineAlignment.Stretch.Name then
					object.Size = UDim2.new(object.Size.X, UDim.new(1, 0))
				end
			else
				local alignment = listConfig.VerticalAlignment

				if alignment == Enum.VerticalAlignment.Bottom.Name then
					position += UDim2.fromOffset(0, parent.AbsoluteSize.Y - object.AbsoluteSize.Y)
				elseif alignment == Enum.VerticalAlignment.Center.Name then
					position += UDim2.fromOffset(0, (parent.AbsoluteSize.Y - object.AbsoluteSize.Y) / 2)
				end
			end
		end

		object.Position = position
		currentPosition += size + paddingPerChild
	end

	if renderUpdateConnectionId and time() - lastChanged > 1 then
		game:GetService("RunService"):UnbindFromRenderStep(renderUpdateConnectionId)
		renderUpdateConnectionId = nil
	end
end

local function onChanged()
	if not renderUpdateConnectionId and time() - lastChanged < 1 then
		renderUpdateConnectionId = game:GetService("HttpService"):GenerateGUID()
		game:GetService("RunService")
			:BindToRenderStep(renderUpdateConnectionId, Enum.RenderPriority.Camera.Value - 1, update)
	end
	lastChanged = time()
end

local function init()
	local parent = script.Parent
	local connections = {}

	importListConfiguration()

	script.Changed:Connect(onChanged)
	parent.Changed:Connect(onChanged)
	parent.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiObject") then
			connections[descendant] = descendant:GetPropertyChangedSignal("AbsoluteSize"):Connect(onChanged)
		end
		onChanged()
	end)
	parent.DescendantRemoving:Connect(function(descendant)
		if connections[descendant] then
			connections[descendant]:Disconnect()
			connections[descendant] = nil
		end

		for i, v in connections do
			if not parent:IsAncestorOf(i) then
				v:Disconnect()
				connections[i] = nil
			end
		end

		onChanged()
	end)
end

init()
