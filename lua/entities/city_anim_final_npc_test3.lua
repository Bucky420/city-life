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
local FOLLOW_START_DIST = 110
local FOLLOW_RUN_DIST = 450
local FOLLOW_LOST_DIST  = 30000

local FOLLOW_SPEED_WALK = 85
local FOLLOW_SPEED_RUN = 150
local FOLLOW_SPEED_IDLE = 60

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

	self.loco:SetDesiredSpeed(60)
	self.loco:SetAcceleration(300)
	self.loco:SetDeceleration(300)
	self.loco:SetStepHeight(18)
	self.loco:SetMaxYawRate(180)

	self:StartActivity(ACT_IDLE)

	self.Commander = nil
	self.NextTurnTime = 0
	self._DesiredSpeed = 0
end

function ENT:BodyUpdate()
	local act = self:GetActivity()
	local speed = self.loco:GetVelocity():Length2D()
	local wantMove = speed > 5

	local newAct = wantMove and ACT_WALK or ACT_IDLE

	if newAct ~= act and newAct then
		local cycle
		if act == ACT_IDLE and newAct == ACT_WALK then
			cycle = self:GetCycle()
		end
		self:StartActivity(newAct)
		if cycle then
			self:SetCycle(cycle)
		end
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
				self._DesiredSpeed = 1

				local toTarget = (cmdPos - self:GetPos()):GetNormalized()
				self.loco:FaceTowards(cmdPos)
				local faceStart = CurTime()
				while self:GetForward():Dot(toTarget) < 0.95 and CurTime() - faceStart < 2 do
					toTarget = (cmdPos - self:GetPos()):GetNormalized()
					self.loco:FaceTowards(cmdPos) 
					coroutine.yield()
				end

				if not self._LastMovePrint or CurTime() - self._LastMovePrint > 5 then
					self._LastMovePrint = CurTime()
					print(self:GetClass() .. " [" .. self:EntIndex() .. "] moving to " .. self.Commander:Nick())
				end
				self._DesiredSpeed = (dist > FOLLOW_RUN_DIST and FOLLOW_SPEED_RUN) or
					(dist > FOLLOW_START_DIST and FOLLOW_SPEED_WALK) or
					FOLLOW_SPEED_IDLE
				self.loco:SetDesiredSpeed(self._DesiredSpeed)

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
				self._DesiredSpeed = 0
				coroutine.wait(1)
			end
		else
			self._DesiredSpeed = 0
			self.Commander = nil
			coroutine.wait(1)
		end
	end
end

end

if CLIENT then

function ENT:FireAnimationEvent(pos, ang, event, name)
    if event >= 6004 and event <= 6007 then
        local seq = self:GetSequence()
        if self._FootEventSeq ~= seq then
            self._FootEventSeq = seq
            self._FootEventLeft = nil
            self._FootEventRight = nil
        end
        local cycle = self:GetCycle()
        if event % 2 == 1 then
            self._FootEventLeft = cycle
        else
            self._FootEventRight = cycle
        end
    end
    if CityNPCs and CityNPCs.DbgEnts and CityNPCs.DbgEnts[self:EntIndex()] then
        print(string.format("[AnimEvent] %s[%d] event=%d name=%s",
            self:GetClass(), self:EntIndex(), event, name or "?"))
    end
end

function ENT:Draw()
	local pos = self:GetPos()
	local STEP_HEIGHT = 18
	-- Step 1: Enable IK on client (server SetIK doesn't propagate to nextbot client entity)
	self:SetIK(true)

	-- SetupBones at ORIGINAL position to get true animated bone positions
	self:SetupBones()

	local lFootBone = self:LookupBone("ValveBiped.Bip01_L_Foot")
	local rFootBone = self:LookupBone("ValveBiped.Bip01_R_Foot")

	-- Get actual bone world positions using matrix (wiki: GetBonePosition can be stale)
	local lFootWorld = nil
	local rFootWorld = nil

	if lFootBone and lFootBone >= 0 then
		local mat = self:GetBoneMatrix(lFootBone)
		if mat then lFootWorld = mat:GetTranslation() end
	end
	if rFootBone and rFootBone >= 0 then
		local mat = self:GetBoneMatrix(rFootBone)
		if mat then rFootWorld = mat:GetTranslation() end
	end

	-- Step 2: Trace from each foot's ACTUAL world position
	local r = 3
	local TRACE_DIST = 48

	local lGroundZ, rGroundZ = nil, nil
	local lTrDistNum, rTrDistNum

	if lFootWorld then
		local lEnd = lFootWorld - Vector(0, 0, TRACE_DIST)
		local lTr = util.TraceHull({
			start = lFootWorld,
			endpos = lEnd,
			mins = Vector(-r, -r, 0),
			maxs = Vector(r, r, 1),
			filter = self,
			mask = MASK_SOLID
		})
		if lTr.Hit then
			lTrDistNum = lFootWorld.z - lTr.HitPos.z
			lGroundZ = lTr.HitPos.z
		end
		-- Visualize left foot trace when debug is on (requires developer 1)
		if CityNPCs and CityNPCs.DbgEnts and CityNPCs.DbgEnts[self:EntIndex()] then
			local col = lTr.Hit and Color(0, 255, 0) or Color(255, 0, 0)
			local endPos = lTr.Hit and lTr.HitPos or lEnd
			debugoverlay.Cross(lFootWorld, r, 0.01, col, true)
			debugoverlay.Cross(endPos, r, 0.01, col, true)
			debugoverlay.Line(lFootWorld, endPos, 0.01, col, true)
		end
	end

	if rFootWorld then
		local rEnd = rFootWorld - Vector(0, 0, TRACE_DIST)
		local rTr = util.TraceHull({
			start = rFootWorld,
			endpos = rEnd,
			mins = Vector(-r, -r, 0),
			maxs = Vector(r, r, 1),
			filter = self,
			mask = MASK_SOLID
		})
		if rTr.Hit then
			rTrDistNum = rFootWorld.z - rTr.HitPos.z
			rGroundZ = rTr.HitPos.z
		end
		-- Visualize right foot trace when debug is on
		if CityNPCs and CityNPCs.DbgEnts and CityNPCs.DbgEnts[self:EntIndex()] then
			local col = rTr.Hit and Color(0, 255, 0) or Color(255, 0, 0)
			local endPos = rTr.Hit and rTr.HitPos or rEnd
			debugoverlay.Cross(rFootWorld, r, 0.01, col, true)
			debugoverlay.Cross(endPos, r, 0.01, col, true)
			debugoverlay.Line(rFootWorld, endPos, 0.01, col, true)
		end
	end

	-- Step 3: Per-foot plant weight from FireAnimationEvent
	local lFootWeight = 1
	local rFootWeight = 1
	if self._FootEventLeft and self._FootEventRight then
		local cycle = self:GetCycle()

		local ld = math.abs(cycle - self._FootEventLeft)
		lFootWeight = math.Clamp(1 - ld * 2, 0, 1)

		local rd = math.abs(cycle - self._FootEventRight)
		rFootWeight = math.Clamp(1 - rd * 2, 0, 1)
	end

	-- Step 4: Weighted blend of both foot grounds, smoothed by 0.2/0.8 debounce
	local totalWeight = 0
	local sumZ = 0
	if lGroundZ then
		sumZ = sumZ + lGroundZ * lFootWeight
		totalWeight = totalWeight + lFootWeight
	end
	if rGroundZ then
		sumZ = sumZ + rGroundZ * rFootWeight
		totalWeight = totalWeight + rFootWeight
	end

	if totalWeight > 0.01 then
		local blendZ = sumZ / totalWeight

		if not self._EstIkFloor then
			self._EstIkFloor = blendZ
		end
		self._EstIkFloor = self._EstIkFloor * 0.8 + blendZ * 0.2

		self._IkOffset = math.Clamp(self._EstIkFloor - pos.z, -STEP_HEIGHT, 0)
	else
		self._IkOffset = (self._IkOffset or 0) * 0.5
	end

	-- Debug via citynpc_debug_entity (external Think hook in city_npcs_init.lua)

	-- Step 5: Apply offset and draw
	self:SetPos(Vector(pos.x, pos.y, pos.z + (self._IkOffset or 0)))
	self:SetupBones()
	self:DrawModel()
	self:SetPos(pos)
end

end
