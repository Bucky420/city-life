AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"

ENT.PrintName = "Final Anim Test NPC v3"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"

ENT.Purpose = "Minimal follow NPC with SetIK(true)"
ENT.Instructions = "Press +USE to recruit. Follows commander."

local FOLLOW_STOP_DIST = 75
local FOLLOW_RUN_DIST = 450
local FOLLOW_LOST_DIST = 30000

local FOLLOW_SPEED_WALK = 75
local FOLLOW_SPEED_RUN = 150

local TURN_GESTURE_COOLDOWN = 0.5
local TURN_GESTURE_MIN_DELTA = 15

if SERVER then

function ENT:Initialize()
	self:SetModel("models/Humans/Group03/male_01.mdl")

	self:SetIK(true)

	self:PhysicsInit(SOLID_BBOX)
	self:SetMoveType(MOVETYPE_STEP)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionGroup(COLLISION_GROUP_NPC)

	self:SetHealth(100)
	self:SetMaxHealth(100)

	self:SetUseType(SIMPLE_USE)

	self.loco:SetDesiredSpeed(150)
	self.loco:SetAcceleration(200)
	self.loco:SetDeceleration(200)
	self.loco:SetStepHeight(18)
	self.loco:SetMaxYawRate(180)

	self:StartActivity(ACT_IDLE)

	self.Commander = nil
	self.NextTurnTime = 0
end

function ENT:BodyUpdate()
	local act = self:GetActivity()
	local speed = self.loco:GetVelocity():Length2D()
	local wantMove = speed > 20

	if wantMove then
		local seqIdx = self:LookupSequence("plaza_walk_all")
		if seqIdx and seqIdx >= 0 then
			if self:GetSequence() ~= seqIdx then
				self:SetSequence(seqIdx)
			end
			self._UsingPlazaWalk = true
		elseif act ~= ACT_WALK then
			self._UsingPlazaWalk = nil
			self:StartActivity(ACT_WALK)
		end
	elseif self._UsingPlazaWalk or act ~= ACT_IDLE then
		self._UsingPlazaWalk = nil
		self:StartActivity(ACT_IDLE)
	end

	self:BodyMoveXY()
end

function ENT:AcceptInput(name, activator)
	if name ~= "Use" then return end
	if not IsValid(activator) or not activator:IsPlayer() or not activator:Alive() then return end

	self.Commander = (self.Commander == activator) and nil or activator
	return true
end

function ENT:AddTurnGesture(yawDeltaDeg)
	if CurTime() < self.NextTurnTime then return end
	self.NextTurnTime = CurTime() + TURN_GESTURE_COOLDOWN

	local absDelta = math.abs(yawDeltaDeg)
	if absDelta < TURN_GESTURE_MIN_DELTA then return end

	local turnAct
	if yawDeltaDeg < -45 then
		turnAct = ACT_GESTURE_TURN_RIGHT90
	elseif yawDeltaDeg < 0 then
		turnAct = ACT_GESTURE_TURN_RIGHT45
	elseif yawDeltaDeg <= 45 then
		turnAct = ACT_GESTURE_TURN_LEFT45
	else
		turnAct = ACT_GESTURE_TURN_LEFT90
	end

	local seqIdx = self:SelectWeightedSequence(turnAct)
	if seqIdx and seqIdx >= 0 then
		local layerId = self:AddGestureSequence(seqIdx, true)
		if layerId and layerId >= 0 then
			self:SetLayerPriority(layerId, 100)
		end
	end
end

function ENT:RunBehaviour()
	while self:IsValid() and self:Health() > 0 do
		
		if self.Commander and IsValid(self.Commander) and self.Commander:Alive() then
			local cmdPos = self.Commander:GetPos()
			local dist = self:GetPos():Distance(cmdPos)

			if dist > FOLLOW_LOST_DIST then
				coroutine.wait(1)
				continue
			end

		if dist > FOLLOW_STOP_DIST then

				local toTarget = (cmdPos - self:GetPos()):GetNormalized()
				self.loco:FaceTowards(cmdPos)
				local faceStart = CurTime()
				while self:GetForward():Dot(toTarget) < 0.9 and CurTime() - faceStart < 0.5 do
					toTarget = (cmdPos - self:GetPos()):GetNormalized()
					self.loco:FaceTowards(cmdPos)
					coroutine.yield()
				end

				if not self._LastMovePrint or CurTime() - self._LastMovePrint > 5 then
					self._LastMovePrint = CurTime()
					print(self:GetClass() .. " [" .. self:EntIndex() .. "] moving to " .. self.Commander:Nick())
				end
				self.loco:SetDesiredSpeed(FOLLOW_SPEED_WALK)

				local stuckPos = self:GetPos()
				local stuckTime = 0

				while self.Commander and IsValid(self.Commander) and self.Commander:Alive() do
					cmdPos = self.Commander:GetPos()
					dist = self:GetPos():Distance(cmdPos)

					if dist > FOLLOW_LOST_DIST then
						break
					end
					if dist <= FOLLOW_STOP_DIST then
						break
					end

					self.loco:SetDesiredSpeed((dist > FOLLOW_RUN_DIST and FOLLOW_SPEED_RUN) or
						FOLLOW_SPEED_WALK)

					if self:GetPos():Distance(stuckPos) < 8 then
						stuckTime = stuckTime + FrameTime()
					else
						stuckPos = self:GetPos()
						stuckTime = 0
					end

					if stuckTime > 2 then
						print(self:GetClass() .. " [" .. self:EntIndex() .. "] is stuck, retrying...")
						break
					end

					self.loco:FaceTowards(cmdPos)
					self.loco:Approach(cmdPos, 1)

					local yawDelta = (math.deg(math.atan2(cmdPos.y - self:GetPos().y, cmdPos.x - self:GetPos().x)) - self:GetAngles().y) % 360
					if yawDelta > 180 then yawDelta = yawDelta - 360 end
					self:AddTurnGesture(yawDelta)

					coroutine.yield()
				end
			else
				coroutine.wait(1)
			end
		else
			self.Commander = nil
			coroutine.wait(1)
		end
	end
end

end

if CLIENT then

-- Model footstep events are baked into the .mdl file and never change at runtime.
-- Cache once per model, shared across all NPCs using the same model.
local modelFootCycleCache = {}

function ENT:Initialize()
	local model = self:GetModel()
	if not modelFootCycleCache[model] then
		local cache = {}
		local mi = util.GetModelInfo(model)
		if mi and mi.Sequences then
			for _, seq in ipairs(mi.Sequences) do
				local evt6006, evt6007
				for _, ev in ipairs(seq.Events) do
					if ev.Event == 6006 then evt6006 = ev.Cycle end
					if ev.Event == 6007 then evt6007 = ev.Cycle end
				end
				if evt6006 and evt6007 then
					cache[seq.Name] = { left = evt6006, right = evt6007 }
				end
			end
		end
		modelFootCycleCache[model] = cache
	end
end

function ENT:Draw()
	self:SetIK(true)
	self:SetupBones()

	local lFootBone = self:LookupBone("ValveBiped.Bip01_L_Foot")
	local rFootBone = self:LookupBone("ValveBiped.Bip01_R_Foot")

	local STEP_HEIGHT = 18
	local HULL_R = 2.5
	local PLANTED_FOOT_Z = 5.5
	local hullPos = self:GetPos()
	local hullZ = hullPos.z
	local traceZ = self._VisualZ or self._LastGroundZ or hullZ

	-- Determine which foot is planted using the animation cycle
	local model = self:GetModel()
	if model and not modelFootCycleCache[model] then
		self:Initialize()
	end
	local footCycle = model and modelFootCycleCache[model] and modelFootCycleCache[model][self:GetSequenceName(self:GetSequence())]
	local cycle = self:GetCycle()
	local activeFoot
	if footCycle then
		local function cycleDist(a, b)
			local d = math.abs(a - b)
			return math.min(d, math.abs(d - 1))
		end
		activeFoot = (cycleDist(cycle, footCycle.left) < cycleDist(cycle, footCycle.right)) and "left" or "right"
	else
		activeFoot = "left"
	end

	-- Movement detection for debug
	local actSeq = self:GetSequenceName(self:GetSequence())
	local isMoving = actSeq and (actSeq:lower():find("walk") or actSeq:lower():find("run"))
	local running = FrameTime() > 0

	-- Hull-centered traces: centered at hullZ, span ±StepHeight
	local function doTrace(bone, footName)
		if not bone then return nil end
		local mat = self:GetBoneMatrix(bone)
		if not mat then return nil end
		local footPos = mat:GetTranslation()
		local tr = util.TraceHull({
			start = Vector(footPos.x, footPos.y, traceZ + STEP_HEIGHT + 2),
			endpos = Vector(footPos.x, footPos.y, traceZ - STEP_HEIGHT - 2),
			mins = Vector(-HULL_R, -HULL_R, 0),
			maxs = Vector(HULL_R, HULL_R, 1),
			filter = self,
			mask = MASK_SOLID
		})
		if isMoving and running and tr.Hit then
			print("TRACE " .. footName .. " hitZ=" .. tr.HitPos.z .. " traceZ=" .. traceZ .. " diff=" .. (tr.HitPos.z - traceZ))
		end
		return tr.Hit and tr.HitPos.z or nil
	end

	local leftHit = doTrace(lFootBone, "L")
	local rightHit = doTrace(rFootBone, "R")

	-- Only trust the active foot if its bone is near the ground (planted)
	local function footLocalZ(bone)
		if not bone then return nil end
		local m = self:GetBoneMatrix(bone)
		if not m then return nil end
		return self:WorldToLocal(m:GetTranslation()).z
	end
	local activeLocalZ = (activeFoot == "left") and footLocalZ(lFootBone) or footLocalZ(rFootBone)
	local activePlanted = activeLocalZ and activeLocalZ < PLANTED_FOOT_Z

	-- Use only the active planted foot. If it is swinging, hold the last ground
	-- instead of letting the trailing foot pull us back down to an old tread.
	local groundZ
	if activeFoot == "left" then
		groundZ = (activePlanted and leftHit) or self._LastGroundZ or leftHit or rightHit
	else
		groundZ = (activePlanted and rightHit) or self._LastGroundZ or rightHit or leftHit
	end

	if isMoving and running then
		local function localFootZ(bone)
			if not bone then return "?" end
			local m = self:GetBoneMatrix(bone)
			if not m then return "?" end
			return string.format("%.1f", self:WorldToLocal(m:GetTranslation()).z)
		end
		print("CYCLE=" .. string.format("%.3f", cycle) .. " active=" .. activeFoot .. " Lz=" .. localFootZ(lFootBone) .. " Rz=" .. localFootZ(rFootBone) .. " gZ=" .. (groundZ and string.format("%.1f", groundZ) or "nil"))
	end

	if groundZ then
		-- Clamp to our visual ground estimate, not the NextBot hull. The hull can
		-- step up before the planted foot reaches the next tread.
		groundZ = math.Clamp(groundZ, traceZ - STEP_HEIGHT, traceZ + STEP_HEIGHT)

		self._LastGroundZ = groundZ
		self._VisualZ = Lerp(0.06, self._VisualZ or groundZ, groundZ)
		local newPos = Vector(hullPos.x, hullPos.y, self._VisualZ)

		self:SetPos(newPos)
		self:SetupBones()
		self:DrawModel()
		self:SetPos(hullPos)
	else
		self:DrawModel()
	end
end

end
