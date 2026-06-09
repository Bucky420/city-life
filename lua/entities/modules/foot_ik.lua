CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local FootIK = CityNPCs.Modules.foot_ik or {}
CityNPCs.Modules.foot_ik = FootIK

function FootIK.IsCycleInRelease(rule, cycle)
	if not rule then return false end
	local peak = rule.peak or rule.start or 0
	local tail = rule.tail or peak
	local finish = rule.finish or tail
	if tail < peak then tail = tail + 1 end
	if finish < peak then finish = finish + 1 end
	if cycle < peak then cycle = cycle + 1 end
	if cycle < peak or cycle >= finish then return false end
	if cycle <= tail then return true end
	return ((cycle - tail) / math.max(finish - tail, 0.001)) < 0.1
end

function FootIK.UpdateFoot(ent, side, hitZ, rule, cycle)
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
	end

	if active and hitZ and not state.latched then
		state.latched = true
		state.height = hitZ
		state.rule = rule
		state.lastCycle = cycle
	elseif active and state.latched then
		state.rule = rule
		state.lastCycle = cycle
	elseif not active then
		state.latched = false
		state.height = nil
		state.rule = nil
	end

	return state.latched and state.height or nil, state
end

function FootIK.GetCommittedHeights(ent, data)
	local heights = {}
	local activeFoot = data.activeFoot

	local leftHeight = FootIK.UpdateFoot(ent, "left", data.leftHit, data.leftRule, data.cycle)
	local rightHeight = FootIK.UpdateFoot(ent, "right", data.rightHit, data.rightRule, data.cycle)
	local activeHeight = activeFoot == "left" and leftHeight or rightHeight

	if activeHeight then heights[#heights + 1] = activeHeight end
	if not activeHeight and leftHeight then heights[#heights + 1] = leftHeight end
	if not activeHeight and rightHeight then heights[#heights + 1] = rightHeight end

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
