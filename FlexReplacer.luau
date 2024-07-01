--[[
	Utility script that replaces all UIListLayouts with a custom drop-in replacement
--]]

local function replaceFlexList(list: UIListLayout)
	local s = script.FlexList:Clone()
	s.Parent = list.Parent
	return s
end

local function main()
	local scripts = {}

	for _, desc in script.Parent:GetDescendants() do
		if desc:IsA("UIListLayout") then
			table.insert(scripts, replaceFlexList(desc))
		end
	end

	for _, v in scripts do
		v.Enabled = true
	end

	script:Destroy()
end

main()
