CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local FootIK = CityNPCs.Modules.foot_ik or {}
CityNPCs.Modules.foot_ik = FootIK

local function normalizeCycle(rule, cycle)
	if rule and rule.finish and rule.finish > 1 and cycle < rule.start then
		return cycle + 1
	end
	return cycle
end

function FootIK.IsCycleInRelease(rule, cycle)
	if not rule then return false end
	cycle = normalizeCycle(rule, cycle)
	if cycle < rule.peak or cycle >= rule.finish then return false end
	if cycle <= rule.tail then return true end
	return ((cycle - rule.tail) / math.max(rule.finish - rule.tail, 0.001)) < 0.1
end

function FootIK.UpdateFoot(ent, side, hitZ, rule, cycle, fallbackAge, fallbackWindow)
	if not IsValid(ent) then return nil end
	ent._CityFootIK = ent._CityFootIK or {}

	local state = ent._CityFootIK[side]
	if not state then
		state = {}
		ent._CityFootIK[side] = state
	end

	local active = false
	if rule then
		active = FootIK.IsCycleInRelease(rule, cycle)
	elseif fallbackAge and fallbackWindow then
		active = fallbackAge <= fallbackWindow
	end

	if active and hitZ then
		state.latched = true
		state.height = hitZ
		state.rule = rule
		state.lastCycle = cycle
	elseif not active then
		state.latched = false
		state.rule = nil
	end

	return state.latched and state.height or nil, state
end

function FootIK.GetCommittedHeights(ent, data)
	local heights = {}
	local activeFoot = data.activeFoot
	local activeHit = activeFoot == "left" and data.leftHit or data.rightHit
	local activeRule = activeFoot == "left" and data.leftRule or data.rightRule
	local activeAge = activeFoot == "left" and data.leftAge or data.rightAge

	local activeHeight = FootIK.UpdateFoot(ent, activeFoot or "left", activeHit, activeRule, data.cycle, activeAge, data.fallbackWindow)
	if activeHeight then
		heights[#heights + 1] = activeHeight
	else
		local leftHeight = FootIK.UpdateFoot(ent, "left", data.leftHit, data.leftRule, data.cycle, data.leftAge, data.fallbackWindow)
		local rightHeight = FootIK.UpdateFoot(ent, "right", data.rightHit, data.rightRule, data.cycle, data.rightAge, data.fallbackWindow)
		if leftHeight then heights[#heights + 1] = leftHeight end
		if rightHeight then heights[#heights + 1] = rightHeight end
		if #heights == 0 then
			if data.leftHit and data.leftPlanted then heights[#heights + 1] = data.leftHit end
			if data.rightHit and data.rightPlanted then heights[#heights + 1] = data.rightHit end
		end
	end

	return heights
end

function FootIK.MinMax(heights)
	local minZ
	local maxZ
	for _, height in ipairs(heights or {}) do
		minZ = minZ and math.min(minZ, height) or height
		maxZ = maxZ and math.max(maxZ, height) or height
	end
	return minZ, maxZ
end

return FootIK
