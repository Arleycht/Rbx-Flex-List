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

local function filter<A>(t: { A }, f: (A) -> boolean): { A }
	local u = {}
	for _, v in t do
		if f(v) then
			table.insert(u, v)
		end
	end
	return u
end

local function fold<A, B>(t: { A }, f: (B, A) -> B, init: B): B
	local u = init
	for _, v in t do
		u = f(u, v)
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

local function importFlexConfiguration(object: GuiObject, config)
	local flexItemConfiguration = object:FindFirstChildWhichIsA("UIFlexItem")
	if flexItemConfiguration then
		config.FlexMode = flexItemConfiguration.FlexMode.Name
		config.ItemLineAlignment = flexItemConfiguration.ItemLineAlignment.Name
		flexItemConfiguration:Destroy()
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

		importFlexConfiguration(object, flexConfig)

		return flexConfig
	end

	local config = {
		FlexMode = Enum.UIFlexMode.None.Name,
		GrowRatio = 0,
		ItemLineAlignment = Enum.ItemLineAlignment.Automatic.Name,
		ShrinkRatio = 0,
	}

	importFlexConfiguration(object, config)

	return config
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

local function calculateFlex(values: { number }, ratios: { Vector2 }, target: number)
	local sum = fold(values, function(b: number, a: number)
		return b + a
	end, 0)
	local totalRatio = fold(ratios, function(b: Vector2, a: Vector2)
		return b + a
	end, Vector2.zero)
	local available = target - sum

	-- Round size deltas to nearest integer value while conserving the desired total
	local newValues = {}
	for i, v in values do
		local ratio = ratios[i].X / totalRatio.X
		if available < 0 then
			ratio = ratios[i].Y / totalRatio.Y
		end
		newValues[i] = v + (available * ratio)
	end

	return roundAllocations(newValues, target)
end

local function update()
	local parent = script.Parent :: GuiObject
	local listConfig = getListConfiguration()
	local isVertical = (listConfig.FillDirection == Enum.FillDirection.Vertical.Name)
	local flex = listConfig.VerticalFlex
	local crossFlex = listConfig.HorizontalFlex

	local totalSpace = parent.AbsoluteSize
	local totalPadding = Vector2.new()
	local totalChildrenSpace = Vector2.new()
	local totalRatio = Vector2.zero
	local guiObjects = {}
	local flexObjects = {}
	local flexConfigs = {}

	-- Load configs and calculate sums

	for _, object in parent:GetChildren() do
		if object:IsA("GuiObject") then
			local basis = getBasisSize(object)
			local config = getFlexConfiguration(object)
			flexConfigs[object] = config

			if config.FlexMode ~= Enum.UIFlexMode.None.Name then
				totalRatio += Vector2.new(config.GrowRatio, config.ShrinkRatio)
				table.insert(flexObjects, object)
			end

			totalChildrenSpace += udim2ToAbsolute(basis, totalSpace)
			object.Size = basis
			table.insert(guiObjects, object)
		elseif object:IsA("UIPadding") then
			totalPadding += udim2ToAbsolute(
				UDim2.new(object.PaddingLeft + object.PaddingRight, object.PaddingTop + object.PaddingBottom),
				totalSpace
			)
		end
	end

	-- Flip XY to exploit symmetry

	if not isVertical then
		flex, crossFlex = crossFlex, flex

		totalSpace = Vector2.new(totalSpace.Y, totalSpace.X)
		totalPadding = Vector2.new(totalPadding.Y, totalPadding.X)
		totalChildrenSpace = Vector2.new(totalChildrenSpace.Y, totalChildrenSpace.X)

		for _, object in guiObjects do
			object.Position = UDim2.new(object.Position.Y, object.Position.X)
			object.Size = UDim2.new(object.Size.Y, object.Size.X)
		end
	end

	-- Apply list sort order

	local sortComparator = function(a: GuiObject, b: GuiObject)
		if listConfig.SortOrder == Enum.SortOrder.Name.Name then
			return a.Name < b.Name
		else
			return a.LayoutOrder < b.LayoutOrder
		end
	end

	guiObjects = mergeSort(guiObjects, sortComparator)
	flexObjects = mergeSort(flexObjects, sortComparator)

	-- Flex

	local isFlex = (flex == Enum.UIFlexAlignment.Fill.Name)

	local availableSpace = totalSpace.Y - totalPadding.Y
	local paddingPerChild = listConfig.Padding.Offset + (listConfig.Padding.Scale * totalSpace.Y)
	local listPadding = paddingPerChild * (#guiObjects - 1)
	local flexRows = {}

	if not isFlex then
		for _, object in guiObjects do
			object.Size = getBasisSize(object)
		end
	else
		-- Subtract list padding
		availableSpace -= listPadding

		-- Apply default if everything is not flex, but the list has flex enabled

		if (availableSpace > 0 and totalRatio.X == 0) or (availableSpace < 0 and totalRatio.Y == 0) then
			for object, flexConfig in flexConfigs do
				flexConfig.FlexMode = Enum.UIFlexMode.Fill.Name
				flexConfig.GrowRatio = 1
				flexConfig.ShrinkRatio = 1
				totalRatio += Vector2.one
				table.insert(flexObjects, object)
			end
		end

		-- Calculate wrapping
		if listConfig.Wraps then
			local row = {}
			local currentRow = 0
			local currentSpace = 0

			for i = 1, #flexObjects do
				local size = udimToAbsolute(flexObjects[i].Size.Y, totalSpace.Y)
				currentSpace += size

				table.insert(row, i)

				if currentSpace > availableSpace then
					currentRow += 1
					table.insert(flexRows, row)
					row = {}
				end
			end

			print(flexRows)
		end

		local sizes = map(flexObjects, function(x)
			return udimToAbsolute(x.Size.Y, totalSpace.Y)
		end)
		local ratios = map(flexObjects, function(x)
			return Vector2.new(flexConfigs[x].GrowRatio, flexConfigs[x].ShrinkRatio)
		end)

		local newSizes = calculateFlex(sizes, ratios, availableSpace)
		for i = 1, #newSizes do
			local basis = getBasisSize(flexObjects[i])
			flexObjects[i].Size = UDim2.new(basis.X, UDim.new(0, newSizes[i]))
		end
	end

	-- List layout

	local emptySpace = availableSpace - totalChildrenSpace.Y
	local currentPosition = 0

	if flex == Enum.UIFlexAlignment.SpaceAround.Name then
		paddingPerChild = emptySpace / #guiObjects
		currentPosition = paddingPerChild / 2
	elseif flex == Enum.UIFlexAlignment.SpaceBetween.Name then
		paddingPerChild = emptySpace / (#guiObjects - 1)
	elseif flex == Enum.UIFlexAlignment.SpaceEvenly.Name then
		paddingPerChild = emptySpace / (#guiObjects + 1)
		currentPosition = paddingPerChild
	end

	for _, object in guiObjects do
		local position = UDim2.fromOffset(0, currentPosition)
		local size = udim2ToAbsolute(object.Size, totalSpace)

		local offset = 0
		local stretch = false

		if crossFlex == Enum.UIFlexAlignment.None.Name then
			local alignment = listConfig.HorizontalAlignment

			if alignment == Enum.HorizontalAlignment.Center.Name then
				offset = 0.5
			elseif alignment == Enum.HorizontalAlignment.Right.Name then
				offset = 1
			end
		elseif crossFlex == Enum.UIFlexAlignment.Fill.Name then
			if
				listConfig.ItemLineAlignment == Enum.ItemLineAlignment.Automatic.Name
				or listConfig.ItemLineAlignment == Enum.ItemLineAlignment.Stretch.Name
			then
				stretch = true
			elseif listConfig.ItemLineAlignment == Enum.ItemLineAlignment.End.Name then
				offset = 1
			elseif listConfig.ItemLineAlignment == Enum.ItemLineAlignment.Center.Name then
				offset = 0.5
			end
		elseif crossFlex == Enum.UIFlexAlignment.SpaceEvenly.Name then
			-- TODO: When wrapping is implement, this will have a different outcome than the real implementation
			offset = 0.5
		elseif crossFlex == Enum.UIFlexAlignment.SpaceAround.Name then
			-- TODO: When wrapping is implement, this will have a different outcome than the real implementation
			offset = 0.5
		elseif crossFlex == Enum.UIFlexAlignment.SpaceBetween.Name then
			-- TODO: When wrapping is implement, this will have a different outcome than the real implementation
			offset = 0
		end

		position += UDim2.fromOffset((totalSpace.X - size.X) * offset, 0)

		if stretch then
			object.Size = UDim2.new(UDim.new(1, 0), object.Size.Y)
		end

		object.Position = position
		currentPosition += size.Y + paddingPerChild
	end

	-- Flip XY again to restore actual values

	if not isVertical then
		flex, crossFlex = crossFlex, flex

		totalSpace = Vector2.new(totalSpace.Y, totalSpace.X)
		totalPadding = Vector2.new(totalPadding.Y, totalPadding.X)
		totalChildrenSpace = Vector2.new(totalChildrenSpace.Y, totalChildrenSpace.X)

		for _, object in guiObjects do
			object.Position = UDim2.new(object.Position.Y, object.Position.X)
			object.Size = UDim2.new(object.Size.Y, object.Size.X)
		end
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
