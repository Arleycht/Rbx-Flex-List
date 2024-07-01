--[[
	Utility script that replaces all UIListLayouts with a custom drop-in replacement
--]]

local function main()
	local scripts = {}

	for _, desc in script.Parent:GetDescendants() do
		if desc:IsA("UIListLayout") then
			local s = script.FlexList:Clone()
			s.Parent = desc.Parent
			table.insert(scripts, s)
		end
	end

	for _, v in scripts do
		v.Enabled = true
	end

	script:Destroy()
end

main()
