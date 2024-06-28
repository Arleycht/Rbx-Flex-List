--!strict

type FlexConfig = {
	FlexMode: string,
	GrowRatio: number,
	ItemLineAlignment: string,
	ShrinkRatio: number,
}

local ATTR_BASIS_SIZE = "FlexBasisSize"

local lastChanged = time()
local renderUpdateConnectionId: string?

local function findValue(o: Instance, name: string, className: string): Instance?
	local child = o:FindFirstChild(name)
	if child and child:IsA(className) then
		return child
	end
	return nil
end

local function getFlexConfiguration(object: GuiObject): FlexConfig?
	local config = object:FindFirstChild("FlexConfiguration")

	if config then
		local flexMode = findValue(config, "FlexMode", "StringValue")
		local growRatio = findValue(config, "GrowRatio", "NumberValue")
		local itemLineAlignment = findValue(config, "ItemLineAlignment", "StringValue")
		local shrinkRatio = findValue(config, "ShrinkRatio", "NumberValue")

		if flexMode and growRatio and itemLineAlignment and shrinkRatio then
			local success, result = pcall(function()
				-- Typecheck assertions
				assert(flexMode:IsA("StringValue"))
				assert(growRatio:IsA("NumberValue"))
				assert(itemLineAlignment:IsA("StringValue"))
				assert(shrinkRatio:IsA("NumberValue"))

				local config = {
					FlexMode = flexMode.Value,
					GrowRatio = growRatio.Value,
					ItemLineAlignment = itemLineAlignment.Value,
					ShrinkRatio = shrinkRatio.Value,
				}

				--assert(
				--	table.find(
				--		{ "Custom", "Fill", "Grow", "None", "Shrink"},
				--		config.FlexMode
				--	),
				--	`Invalid FlexMode in {object:GetFullName()}`
				--)
				--assert(
				--	table.find(
				--		{ "Automatic", "Center", "End", "Start", "Stretch"},
				--		config.ItemLineAlignment
				--	),
				--	`Invalid ItemLineAlignment in {object:GetFullName()}`
				--)

				config.GrowRatio = math.max(0, config.GrowRatio)
				config.ShrinkRatio = math.max(0, config.ShrinkRatio)

				return config
			end)

			if success then
				return result
			else
				warn(`Misconfigured FlexConfiguration in {object:GetFullName()}\n{tostring(result)}`)
			end
		else
			warn(`Misconfigured FlexConfiguration in {object:GetFullName()}`)
		end
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
		-- Stabilize default sorting algorithm by sorting layout order
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
	local isVertical = (script:GetAttribute("FillDirection") == Enum.FillDirection.Vertical.Name)
	local flexAlignment = script:GetAttribute("VerticalFlex")
	local crossFlexAlignment = script:GetAttribute("HorizontalFlex")

	if not isVertical then
		flexAlignment, crossFlexAlignment = crossFlexAlignment, flexAlignment
	end

	local isFlex = (flexAlignment == Enum.UIFlexAlignment.Fill.Name)
	local totalSpace = math.round(isVertical and parent.AbsoluteSize.Y or parent.AbsoluteSize.X)
	local totalChildrenSpace = 0
	local totalRatio = Vector2.zero
	local guiObjects = {}
	local flexItems = {}

	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(guiObjects, child)

			local basis = getBasisSize(child)
			totalChildrenSpace += udimToAbsolute(isVertical and basis.Y or basis.X, totalSpace)

			local flexConfig = getFlexConfiguration(child)

			if flexConfig then
				local flexItem = {
					object = child,
					basisSize = getBasisSize(child),
					ratio = Vector2.new(flexConfig.GrowRatio, flexConfig.ShrinkRatio),
					alignment = flexConfig.ItemLineAlignment,
				}
				totalRatio += flexItem.ratio
				table.insert(flexItems, flexItem)
			end
		elseif child:IsA("UIPadding") then
			if isVertical then
				totalChildrenSpace += udimToAbsolute(child.PaddingTop + child.PaddingBottom, totalSpace)
			else
				totalChildrenSpace += udimToAbsolute(child.PaddingLeft + child.PaddingRight, totalSpace)
			end
		end
	end

	if script:GetAttribute("SortOrder") == Enum.SortOrder.LayoutOrder.Name then
		table.sort(guiObjects, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
	else
		table.sort(guiObjects, function(a, b)
			return a.Name < b.Name
		end)
	end

	local availableSpace = totalSpace - totalChildrenSpace
	local paddingPerChild = script:GetAttribute("Padding").Offset + (script:GetAttribute("Padding").Scale * totalSpace)

	-- Flex

	if isFlex then
		availableSpace -= (paddingPerChild * (#guiObjects - 1))

		local deltas = {}

		for _, flexItem in flexItems do
			local ratio = flexItem.ratio / totalRatio
			table.insert(deltas, availableSpace * ((availableSpace > 0) and ratio.X or ratio.Y))
		end

		deltas = roundAllocations(deltas, availableSpace)

		for i, flexItem in flexItems do
			local basis = getBasisSize(flexItem.object)

			if crossFlexAlignment == Enum.UIFlexAlignment.Fill.Name then
				if isVertical then
					flexItem.object.Size = UDim2.new(1, 0, basis.Y.Scale, basis.Y.Offset + deltas[i])
				else
					flexItem.object.Size = UDim2.new(basis.X.Scale, basis.X.Offset + deltas[i], 1, 0)
				end
			else
				if isVertical then
					flexItem.object.Size = basis + UDim2.fromOffset(0, deltas[i])
				else
					flexItem.object.Size = basis + UDim2.fromOffset(deltas[i], 0)
				end
			end
		end
	else
		for _, flexItem in flexItems do
			flexItem.object.Size = getBasisSize(flexItem.object)
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

		if isVertical then
			size = object.AbsoluteSize.Y
			position = UDim2.fromOffset(0, currentPosition)

			local alignment = script:GetAttribute("HorizontalAlignment")
			if alignment == Enum.HorizontalAlignment.Right.Name then
				position += UDim2.fromOffset(parent.AbsoluteSize.X - object.AbsoluteSize.X, 0)
			elseif alignment == Enum.HorizontalAlignment.Center.Name then
				position += UDim2.fromOffset((parent.AbsoluteSize.X - object.AbsoluteSize.X) / 2, 0)
			end
		else
			size = object.AbsoluteSize.X
			position = UDim2.fromOffset(currentPosition, 0)

			local alignment = script:GetAttribute("VerticalAlignment")
			if alignment == Enum.VerticalAlignment.Bottom.Name then
				position += UDim2.fromOffset(0, parent.AbsoluteSize.Y - object.AbsoluteSize.Y)
			elseif alignment == Enum.VerticalAlignment.Center.Name then
				position += UDim2.fromOffset(0, (parent.AbsoluteSize.Y - object.AbsoluteSize.Y) / 2)
			end
		end

		object.Position = position
		currentPosition += size + paddingPerChild
	end

	if time() - lastChanged > 0.5 and renderUpdateConnectionId then
		game:GetService("RunService"):UnbindFromRenderStep(renderUpdateConnectionId)
		renderUpdateConnectionId = nil
	end
end

local function onChanged()
	if not renderUpdateConnectionId and time() - lastChanged < 0.5 then
		renderUpdateConnectionId = game:GetService("HttpService"):GenerateGUID()
		game:GetService("RunService")
			:BindToRenderStep(renderUpdateConnectionId, Enum.RenderPriority.Camera.Value - 1, update)
	end
	lastChanged = time()
end

local function init()
	local parent = script.Parent
	local layout = parent:FindFirstChildWhichIsA("UIListLayout")

	if layout then
		script:SetAttribute("FillDirection", layout.FillDirection.Name)
		script:SetAttribute("HorizontalAlignment", layout.HorizontalAlignment.Name)
		script:SetAttribute("VerticalAlignment", layout.VerticalAlignment.Name)
		script:SetAttribute("SortOrder", layout.SortOrder.Name)
		script:SetAttribute("Padding", layout.Padding)
		layout:Destroy()
	else
		script:SetAttribute("FillDirection", script:GetAttribute("FillDirection") or "Custom")
		script:SetAttribute("HorizontalAlignment", script:GetAttribute("HorizontalAlignment") or "Custom")
		script:SetAttribute("VerticalAlignment", script:GetAttribute("VerticalAlignment") or "Custom")
		script:SetAttribute("SortOrder", script:GetAttribute("SortOrder") or "LayoutOrder")
		script:SetAttribute("Padding", script:GetAttribute("Padding") or UDim.new())
	end

	local connections = {}

	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(onChanged)
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
