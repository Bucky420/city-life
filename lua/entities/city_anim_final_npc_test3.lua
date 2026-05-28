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
	self.loco:SetAcceleration(200)
	self.loco:SetDeceleration(200)
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

local FOOT_BONES = {
	"ValveBiped.Bip01_L_Foot",
	"ValveBiped.Bip01_R_Foot",
	"ValveBiped.Bip01_L_Ankle",
	"ValveBiped.Bip01_R_Ankle",
}

function ENT:Think()
end

function ENT:Draw()
	local pos = self:GetPos()
	local dt = FrameTime()

	self:SetPos(Vector(pos.x, pos.y, pos.z + (self._IkOffset or 0)))
	self:SetupBones()

	if not self._FootCycles then
		self._FootCycles = {}
		local seq = self:GetSequence()
		local seqName = self:GetSequenceName(seq)
		local mdl = self:GetModel()
		local info = util.GetModelInfo(mdl)
		if info and info.Sequences then
			for _, s in ipairs(info.Sequences) do
				if s.Name == seqName and s.Events then
					for _, ev in ipairs(s.Events) do
						if ev.Event >= 6004 and ev.Event <= 6007 then
							table.insert(self._FootCycles, ev.Cycle)
						end
					end
					break
				end
			end
		end
		if #self._FootCycles == 0 then
			self._FootCycles = {0.29, 0.79}
		end
	end

	local cycle = self:GetCycle()

	local minDist = 0.5
	for _, evCycle in ipairs(self._FootCycles) do
		local d = math.abs(cycle - evCycle)
		if d > 0.5 then d = 1.0 - d end
		if d < minDist then
			minDist = d
		end
	end

	local cur = self._IkOffset or 0
	local target = math.Clamp(-minDist * 36, -18, 0)
	self._IkOffset = cur + (target - cur) * math.min(dt * 8, 1)

	self._DbgFrame = (self._DbgFrame or 0) + 1
	if self._DbgFrame % 10 == 0 then
		print(string.format("off:%.1f dist:%.2f cycle:%.2f events:%s | posZ:%.1f seq:%s",
			self._IkOffset or 0,
			minDist,
			cycle,
			table.concat(self._FootCycles, ","),
			pos.z,
			self:GetSequenceName(self:GetSequence())
		))
	end

	self:DrawModel()
	self:SetPos(pos)
end

end
