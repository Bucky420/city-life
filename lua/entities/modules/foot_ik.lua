CityNPCs = CityNPCs or {}
CityNPCs.Modules = CityNPCs.Modules or {}

local FootIK = CityNPCs.Modules.foot_ik or {}
CityNPCs.Modules.foot_ik = FootIK

local FULL_LATCH_EPSILON = 0.999
local CONTACT_RELEASE_LIMIT = 0.1

local function ruleEnd(rule)
	return rule and (rule.finish or rule["end"]) or nil
end

local function normalizeCycle(rule, cycle)
	cycle = cycle or 0
	local finish = ruleEnd(rule)
	if rule and finish and finish > 1 and cycle < (rule.start or 0) then
		return cycle + 1
	end
	return cycle
end

local function simpleSpline(value)
	value = math.Clamp(value or 0, 0, 1)
	return 3 * value * value - 2 * value * value * value
end

function FootIK.GetRuleWeight(rule, cycle)
	if not rule then return 0 end
	cycle = normalizeCycle(rule, cycle)
	local start = rule.start or 0
	local peak = rule.peak or start
	local tail = rule.tail or peak
	local finish = ruleEnd(rule) or tail

	if cycle < start then return 0 end
	if cycle < peak then
		return simpleSpline((cycle - start) / math.max(peak - start, 0.001))
	end
	if cycle < tail then return 1 end
	if cycle < finish then
		return simpleSpline(1 - ((cycle - tail) / math.max(finish - tail, 0.001)))
	end
	return 0
end

function FootIK.GetRuleRelease(rule, cycle)
	if not rule then return 1 end
	cycle = normalizeCycle(rule, cycle)
	local tail = rule.tail or rule.peak or rule.start or 0
	local finish = ruleEnd(rule) or tail
	if cycle <= tail or cycle >= finish then return 0 end
	return math.Clamp((cycle - tail) / math.max(finish - tail, 0.001), 0, 1)
end

function FootIK.ShouldLatch(rule, cycle)
	if not rule then return false end
	cycle = normalizeCycle(rule, cycle)
	return cycle >= (rule.peak or rule.start or 0) and cycle < (ruleEnd(rule) or 0)
end

function FootIK.IsCycleActive(rule, cycle)
	return FootIK.GetRuleWeight(rule, cycle) > 0.001
end

function FootIK.IsCycleCommitted(rule, cycle)
	return FootIK.IsCycleActive(rule, cycle)
		and FootIK.ShouldLatch(rule, cycle)
		and FootIK.GetRuleRelease(rule, cycle) < CONTACT_RELEASE_LIMIT
end

function FootIK.IsCycleInRelease(rule, cycle)
	if not rule then return false end
	cycle = normalizeCycle(rule, cycle)
	local peak = rule.peak or rule.start or 0
	local finish = ruleEnd(rule) or peak
	return cycle >= peak and cycle < finish and FootIK.GetRuleRelease(rule, cycle) > 0
end

local function updateFromRule(state, hitZ, rule, cycle)
	local weight = FootIK.GetRuleWeight(rule, cycle)
	local release = FootIK.GetRuleRelease(rule, cycle)
	local shouldLatch = FootIK.ShouldLatch(rule, cycle)
	local latchInfluence = shouldLatch and weight or 0
	local active = weight > 0.001

	state.rule = rule
	state.active = active
	state.weight = weight
	state.release = release
	state.shouldLatch = shouldLatch
	state.latchedAmount = latchInfluence
	state.height = rule and rule.height or 0
	state.floor = rule and rule.floor or 0
	state.radius = rule and rule.radius or 0
	state.idealHeight = hitZ
	state.contactHeight = nil
	state.committed = false

	if not active then
		state.hasLatch = false
		state.latchedHeight = nil
		state.latchDelta = 0
		state.trackingHeight = nil
		return state
	end

	if hitZ then
		state.trackingHeight = hitZ
	end

	if hitZ and latchInfluence >= FULL_LATCH_EPSILON then
		if not state.hasLatch then
			state.hasLatch = true
			state.latchedHeight = hitZ
		end
		state.latchDelta = (state.latchedHeight or hitZ) - hitZ
	elseif state.hasLatch and latchInfluence > 0 and hitZ then
		state.latchDelta = ((state.latchedHeight or hitZ) - hitZ) * latchInfluence
	elseif latchInfluence <= 0 then
		state.hasLatch = false
		state.latchedHeight = nil
		state.latchDelta = 0
	end

	local solvedHeight
	if hitZ then
		if state.hasLatch and latchInfluence > 0 then
			solvedHeight = hitZ + (state.latchDelta or 0)
		else
			solvedHeight = hitZ
		end
	end

	state.solvedHeight = solvedHeight
	state.committed = active and release < CONTACT_RELEASE_LIMIT and solvedHeight ~= nil
	if state.committed then
		state.contactHeight = solvedHeight
	end

	return state
end

local function updateFallback(state, hitZ, fallbackAge, fallbackWindow)
	local active = hitZ ~= nil and fallbackAge ~= nil and fallbackWindow ~= nil and fallbackAge <= fallbackWindow
	state.rule = nil
	state.active = active
	state.weight = active and 1 or 0
	state.release = 0
	state.shouldLatch = active
	state.latchedAmount = active and 1 or 0
	state.height = 0
	state.floor = 0
	state.radius = 0
	state.idealHeight = hitZ
	state.solvedHeight = hitZ
	state.contactHeight = active and hitZ or nil
	state.committed = active

	if active then
		if not state.hasLatch then
			state.hasLatch = true
			state.latchedHeight = hitZ
		end
		state.trackingHeight = hitZ
	else
		state.hasLatch = false
		state.latchedHeight = nil
		state.trackingHeight = nil
	end

	return state
end

function FootIK.UpdateFoot(ent, side, hitZ, rule, cycle, fallbackAge, fallbackWindow)
	if not IsValid(ent) then return nil end
	ent._CityFootIK = ent._CityFootIK or {}

	local state = ent._CityFootIK[side]
	if not state then
		state = { side = side }
		ent._CityFootIK[side] = state
	end

	state.side = side
	state.lastCycle = cycle

	if rule then
		return updateFromRule(state, hitZ, rule, cycle)
	end
	return updateFallback(state, hitZ, fallbackAge, fallbackWindow)
end

function FootIK.UpdateTargets(ent, data)
	data = data or {}
	local left = FootIK.UpdateFoot(ent, "left", data.leftHit, data.leftRule, data.cycle, data.leftAge, data.fallbackWindow)
	local right = FootIK.UpdateFoot(ent, "right", data.rightHit, data.rightRule, data.cycle, data.rightAge, data.fallbackWindow)

	local heights = {}
	local function add(state)
		if state and state.committed and state.contactHeight then
			heights[#heights + 1] = state.contactHeight
		end
	end

	if data.activeFoot == "right" then
		add(right)
		add(left)
	else
		add(left)
		add(right)
	end

	local minZ, maxZ = FootIK.MinMax(heights)
	return {
		left = left,
		right = right,
		heights = heights,
		minZ = minZ,
		maxZ = maxZ,
		active = data.activeFoot == "right" and right or left
	}
end

function FootIK.GetCommittedHeights(ent, data)
	return FootIK.UpdateTargets(ent, data).heights
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
