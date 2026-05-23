AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"
ENT.PrintName = "HL2 Citizen NPC (IK Test)"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Author = "City NPCs"
ENT.Purpose = "IK test - small fwd/bwd + up/down to drive leg motion"
ENT.Instructions = "Spawn and watch the IK legs."

function ENT:Initialize()
    self:SetModel("models/Humans/Group03/male_01.mdl")
    if SERVER then
        self:PhysicsInit(SOLID_BBOX)
        self:SetMoveType(MOVETYPE_STEP)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionGroup(COLLISION_GROUP_NPC)
        self:SetHealth(100)
        self:SetMaxHealth(100)
        self:SetUseType(SIMPLE_USE)
        self.loco:SetAcceleration(400)
        self.loco:SetDeceleration(400)
        self.loco:SetStepHeight(18)
        self.loco:SetMaxYawRate(360)

        self.Commander = nil
        self.NextBalanceTime = 0.5
        self.Bias = 0
        self.Balanced = false
        self.StepCount = 0
    end
end

function ENT:AcceptInput(name, activator, caller, data)
    if SERVER and name == "Use" and IsValid(activator) and activator:IsPlayer() and activator:Alive() then
        if self.Commander == activator then
            self.Commander = nil
            print("[CityNPC] " .. self:EntIndex() .. " commander deselcted")
        else
            self.Commander = activator
            print("[CityNPC] " .. self:EntIndex() .. " commander set to " .. activator:Nick())
        end
        return true
    end
end

function ENT:BodyUpdate()
    if not SERVER then return end

    if self._Stagger then
        self._Stagger = self._Stagger - 1
        if self._Stagger <= 0 then
            self._Stagger = nil
            if self:GetActivity() ~= ACT_IDLE then self:StartActivity(ACT_IDLE) end
        elseif self:GetActivity() ~= ACT_WALK then
            self:StartActivity(ACT_WALK)
        end
        self:BodyMoveXY()
        return
    end

    local vel = self.loco:GetVelocity():Length2D()
    local act = self:GetActivity()

    if vel > 120 then
        if act ~= ACT_RUN then self:StartActivity(ACT_RUN) end
        self:BodyMoveXY()
    elseif vel < 5 then
        if act == ACT_IDLE then
            self:BodyMoveXY()
        else
            if act ~= ACT_WALK then self:StartActivity(ACT_WALK) end
            if not self._Stagger then
                self._Stagger = 8
            end
            self:BodyMoveXY()
        end
    elseif act == ACT_IDLE then
        if act ~= ACT_WALK then self:StartActivity(ACT_WALK) end
        self:BodyMoveXY()
    elseif act == ACT_RUN and vel < 60 then
        self:StartActivity(ACT_WALK)
        self:BodyMoveXY()
    else
        self:BodyMoveXY()
    end
end

function ENT:GetFootXDis()
    if not self._FootIds then
        local lId = self:LookupBone("ValveBiped.Bip01_L_Foot")
        local rId = self:LookupBone("ValveBiped.Bip01_R_Foot")
        self._FootIds = { lId, rId }
    end
    local lPos = self:GetBonePosition(self._FootIds[1])
    local rPos = self:GetBonePosition(self._FootIds[2])
    if not lPos or not rPos then return nil end
    local lLocal = self:WorldToLocal(lPos)
    local rLocal = self:WorldToLocal(rPos)
    return math.abs(lLocal.x) + math.abs(rLocal.x)
end

function ENT:PublishFootData()
    if not self._FootIds then self:GetFootXDis() end
    local lPos = self:GetBonePosition(self._FootIds[1])
    local rPos = self:GetBonePosition(self._FootIds[2])
    if lPos and rPos then
        local lLocal = self:WorldToLocal(lPos)
        local rLocal = self:WorldToLocal(rPos)
        self:SetNWVector("FootL", lLocal)
        self:SetNWVector("FootR", rLocal)
    end
end

local FOLLOW_STOP_DIST = 75
local FOLLOW_START_DIST = 110
local FOLLOW_RUN_DIST = 450
local FOLLOW_LOST_DIST = 3000

local function DebugPrint(ent, msg)
    print("[CityNPC " .. ent:EntIndex() .. "] " .. msg)
end

function ENT:RunBehaviour()
    while self:IsValid() and self:Health() > 0 do
        if self.Commander and IsValid(self.Commander) and self.Commander:Alive() then
            self.Bias = 0
            self.Balanced = false
            self.StepCount = 0
            self:SetNWFloat("DebugBias", 0)
            self:SetNWBool("DebugBalanced", false)
            self:SetNWInt("DebugStep", 0)
            self:SetNWString("DebugStatus", "FOLLOW")

            local dist = self:GetPos():Distance(self.Commander:GetPos())
            if dist > FOLLOW_LOST_DIST then
                DebugPrint(self, "commander lost (dist=" .. math.Round(dist) .. ")")
                self.Commander = nil
                coroutine.wait(1)
                continue
            end

            if dist > FOLLOW_STOP_DIST then
                local speed = dist > FOLLOW_RUN_DIST and 300 or (dist > FOLLOW_START_DIST and 90 or 50)
                self.loco:SetDesiredSpeed(speed)
                while self.Commander and IsValid(self.Commander) and dist > FOLLOW_STOP_DIST do
                    local cmdPos = self.Commander:GetPos()
                    dist = self:GetPos():Distance(cmdPos)
                    if dist > FOLLOW_LOST_DIST then self.Commander = nil; break end
                    self:SetNWString("DebugStatus", "FOLLOW")
                    self:SetNWFloat("DebugCycle", self:GetFootXDis() or 0)
                    self:PublishFootData()
                    self.loco:FaceTowards(cmdPos)
                    self.loco:Approach(cmdPos, 1)
                    coroutine.yield()
                end
            end

            if self.Commander and IsValid(self.Commander) then
                self:SetNWString("DebugStatus", "IDLE")
                self:SetNWFloat("DebugCycle", self:GetFootXDis() or 0)
                self:PublishFootData()
                self.loco:SetDesiredSpeed(1)
                coroutine.wait(1)
            end
        else
            self.Commander = nil

            if not self.Balanced and CurTime() > self.NextBalanceTime then
                self.NextBalanceTime = CurTime() + 1.2

                local ang = self:GetAngles()
                ang.y = ang.y + math.random(-2, 2)
                self:SetAngles(ang)

                local dir = self.Bias > 0 and -1 or 1
                local startPos = self:GetPos()
                local fwd = self:GetForward()
                local goal = startPos + fwd * 2000 * dir

                self.loco:SetDesiredSpeed(50)
                local aligned = false
                local bestXDis = 999
                local prevXDis = 999
                local xDisAtStart = self:GetFootXDis() or 999
                local breakXDis = 0

                for _ = 1, 30 do
                    self.loco:Approach(goal, 1)
                    coroutine.yield()

                    local xDis = self:GetFootXDis()
                    if not xDis then break end
                    breakXDis = xDis
                    self:SetNWFloat("DebugCycle", xDis)
                    self:PublishFootData()

                    if xDis < 2.5 then
                        aligned = true
                        break
                    end

                    if xDis < bestXDis then
                        bestXDis = xDis
                    end

                    if prevXDis ~= 999 and xDis > prevXDis + 0.3 and bestXDis < xDisAtStart - 0.5 then
                        aligned = true
                        break
                    end

                    prevXDis = xDis
                end

                self.loco:SetDesiredSpeed(0)
                local delta = (self:GetPos() - startPos):Dot(fwd)
                self.Bias = delta * 0.5
                self.StepCount = self.StepCount + 1

                local bal = self.StepCount >= 6
                if bal then self.Balanced = true end

                self:SetNWFloat("DebugBias", self.Bias)
                self:SetNWBool("DebugBalanced", self.Balanced)
                self:SetNWInt("DebugStep", self.StepCount)
                self:SetNWString("DebugStatus", bal and "BALANCED" or (aligned and "ALIGNED" or "GOAL"))
            end

            coroutine.yield()
        end
    end
end

if CLIENT then
    surface.CreateFont("CityNPCDebug", {
        font = "Consolas",
        size = 14,
        weight = 600
    })

    -- ============================================================
    -- CVARS
    -- ============================================================
    local IK_CVARS = {}
    local CVAR_MAP = {
        { k = "enabled",             c = "ik_foot",                       t = "bool",  d = true,  mn = 0,   mx = 1 },
        { k = "lean_enabled",        c = "ik_foot_lean",                  t = "bool",  d = false, mn = 0,   mx = 1 },
        { k = "ground_distance",     c = "ik_foot_ground_distance",       t = "float", d = 45,    mn = 20,  mx = 100 },
        { k = "smoothing",           c = "ik_foot_smoothing",             t = "float", d = 17,    mn = 1,   mx = 50 },
        { k = "leg_length",          c = "ik_foot_leg_length",            t = "float", d = 45,    mn = 30,  mx = 60 },
        { k = "trace_start_offset",  c = "ik_foot_trace_start_offset",    t = "float", d = 30,    mn = 20,  mx = 40 },
        { k = "sole_offset",         c = "ik_foot_sole_offset",           t = "float", d = 0,     mn = 0,   mx = 5 },
        { k = "uneven_drop_scale",   c = "ik_foot_uneven_drop_scale",     t = "float", d = 0.15,  mn = 0,   mx = 1 },
        { k = "extra_body_drop",     c = "ik_foot_extra_body_drop",       t = "float", d = 0.3,   mn = 0,   mx = 5 },
        { k = "extra_body_drop_uneven", c = "ik_foot_extra_body_drop_uneven", t = "float", d = 1.2, mn = 0, mx = 10 },
        { k = "high_foot_bend_boost", c = "ik_foot_high_foot_bend_boost", t = "float", d = 1.70,  mn = 1,   mx = 2 },
        { k = "foot_rotation_scale", c = "ik_foot_rotation_scale",        t = "float", d = 0.15,  mn = 0,   mx = 1 },
        { k = "lock_strength",       c = "ik_foot_lock_strength",         t = "float", d = 0.85,  mn = 0.1, mx = 2 },
        { k = "release_speed",       c = "ik_foot_release_speed",         t = "float", d = 65,    mn = 5,   mx = 200 },
        { k = "rotation_smoothing",  c = "ik_foot_rotation_smoothing",    t = "float", d = 20,    mn = 1,   mx = 60 },
        { k = "max_body_drop",       c = "ik_foot_max_body_drop",         t = "float", d = 42,    mn = 15,  mx = 80 },
        { k = "stabilize_idle",      c = "ik_foot_stabilize_idle",        t = "bool",  d = true,  mn = 0,   mx = 1 },
        { k = "idle_velocity",       c = "ik_foot_idle_velocity",         t = "float", d = 5,     mn = 1,   mx = 20 },
        { k = "auto_model_detect",   c = "ik_foot_auto_model_detect",     t = "bool",  d = true,  mn = 0,   mx = 1 },
        { k = "anti_clip",           c = "ik_foot_anti_clip",             t = "bool",  d = true,  mn = 0,   mx = 1 },
        { k = "dynamic_sole",        c = "ik_foot_dynamic_sole",          t = "bool",  d = true,  mn = 0,   mx = 1 },
        { k = "stair_step_min_height", c = "ik_foot_stair_step_min_height", t = "float", d = 6,   mn = 2,   mx = 24 },
        { k = "stair_step_max_height", c = "ik_foot_stair_step_max_height", t = "float", d = 28,  mn = 8,   mx = 50 },
        { k = "stair_sequence_window", c = "ik_foot_stair_sequence_window", t = "float", d = 0.33, mn = 0.12, mx = 1.2 },
        { k = "stair_release_multiplier", c = "ik_foot_stair_release_multiplier", t = "float", d = 1.2, mn = 0.8, mx = 2.5 },
        { k = "stair_adaptive_maxstep", c = "ik_foot_stair_adaptive_maxstep", t = "float", d = 1.0, mn = 0.25, mx = 2.0 },
        { k = "moving_surface_max_speed", c = "ik_foot_moving_surface_max_speed", t = "float", d = 45, mn = 5, mx = 180 },
    }
    for _, e in ipairs(CVAR_MAP) do
        local val = e.t == "bool" and (e.d and "1" or "0") or tostring(e.d)
        local cvar = CreateClientConVar(e.c, val, true, true, "")
        IK_CVARS[e.k] = { c = cvar, t = e.t, d = e.d, mn = e.mn, mx = e.mx }
    end

    local function GetIKParam(key)
        local entry = IK_CVARS[key]
        if not entry then return 0 end
        return math.Clamp(entry.c:GetFloat(), entry.mn, entry.mx)
    end
    local function GetIKParamBool(key)
        local entry = IK_CVARS[key]
        if not entry then return false end
        return entry.c:GetBool()
    end

    -- ============================================================
    -- CONSTANTS
    -- ============================================================
    local MAX_KNEE_BEND = 68
    local MIN_KNEE_BEND = -30
    local MAX_FOOT_PITCH = 25
    local MAX_FOOT_ROLL = 20
    local CLUSTER_TOLERANCE = 3.0
    local WALKABLE_Z = 0.35
    local CROUCH_BLEND_TIME = 0.3
    local AIR_BODY_DROP_MAX = 6
    local AIR_KNEE_MIN = 8
    local AIR_KNEE_MAX = 24
    local AIR_FOOT_PITCH_ASCEND = -6
    local AIR_FOOT_PITCH_DESCEND = 14
    local AIR_SWING_SPEED = 6
    local AIR_SWING_AMP = 4
    local REFERENCE_LEG_LENGTH = 45
    local IDLE_ACQUIRE_DELAY = 0.14

    local SAMPLE_WEIGHTS = {
        center = 4, toe = 2, heel = 2,
        left = 2, right = 2,
        toeInner = 1, toeOuter = 1, inner = 1, outer = 1,
    }

    -- ============================================================
    -- HELPERS
    -- ============================================================
    local function IsFiniteNumber(v)
        return isnumber(v) and v == v and v > -math.huge and v < math.huge
    end
    local function IsFiniteVector(vec)
        return isvector(vec) and IsFiniteNumber(vec.x) and IsFiniteNumber(vec.y) and IsFiniteNumber(vec.z)
    end
    local function IsWalkable(normal)
        return normal and normal.z >= WALKABLE_Z
    end
    local function IsReasonableBonePosition(ent, pos)
        if not (IsValid(ent) and IsFiniteVector(pos)) then return false end
        local entPos = ent:GetPos()
        if not IsFiniteVector(entPos) then return false end
        return pos:DistToSqr(entPos) <= (260 * 260)
    end
    local function GetBoneWorldTransform(ent, bone)
        if not bone or bone < 0 then return nil, nil end
        if ent.GetBoneMatrix then
            local matrix = ent:GetBoneMatrix(bone)
            if matrix then
                local pos = matrix:GetTranslation()
                local ang = matrix:GetAngles()
                if IsFiniteVector(pos) and IsReasonableBonePosition(ent, pos) and ang then
                    return pos, ang
                end
            end
        end
        local pos, ang = ent:GetBonePosition(bone)
        if IsFiniteVector(pos) and IsReasonableBonePosition(ent, pos) and ang then
            return pos, ang
        end
        return nil, nil
    end
    local function IsCrouching(ent)
        if ent.Crouching then return ent:Crouching() end
        return false
    end
    local function CanManipulateBones(ent)
        if not IsValid(ent) then return false end
        if ent.InVehicle and ent:InVehicle() then return false end
        return true
    end

    -- ============================================================
    -- SPRING MATH
    -- ============================================================
    local function SpringScalar(current, velocity, target, smoothTime, dt)
        if not (IsFiniteNumber(current) and IsFiniteNumber(velocity) and IsFiniteNumber(target)) then
            return IsFiniteNumber(target) and target or 0, 0
        end
        smoothTime = math.max(smoothTime, 0.0001)
        local omega = 2 / smoothTime
        local x = omega * dt
        local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        local change = current - target
        local temp = (velocity + omega * change) * dt
        local newVelocity = (velocity - omega * temp) * exp
        local newValue = target + (change + temp) * exp
        if not IsFiniteNumber(newValue) then return IsFiniteNumber(target) and target or 0, 0 end
        if not IsFiniteNumber(newVelocity) then newVelocity = 0 end
        return newValue, newVelocity
    end
    local function SpringVector(current, velocity, target, smoothTime, dt)
        local x, xv = SpringScalar(current.x, velocity.x, target.x, smoothTime, dt)
        local y, yv = SpringScalar(current.y, velocity.y, target.y, smoothTime, dt)
        local z, zv = SpringScalar(current.z, velocity.z, target.z, smoothTime, dt)
        return Vector(x, y, z), Vector(xv, yv, zv)
    end
    local function SpringAngle(current, velocity, target, smoothTime, dt)
        local targetP = current.p + math.AngleDifference(target.p, current.p)
        local targetY = current.y + math.AngleDifference(target.y, current.y)
        local targetR = current.r + math.AngleDifference(target.r, current.r)
        local p, pv = SpringScalar(current.p, velocity.p, targetP, smoothTime, dt)
        local y, yv = SpringScalar(current.y, velocity.y, targetY, smoothTime, dt)
        local r, rv = SpringScalar(current.r, velocity.r, targetR, smoothTime, dt)
        return Angle(p, y, r), Angle(pv, yv, rv)
    end
    local SPRING_FIELDS = {"leftThigh", "leftCalf", "leftFoot", "rightThigh", "rightCalf", "rightFoot"}

    -- ============================================================
    -- BLEND STATE
    -- ============================================================
    local function GetIKBlendState(ent)
        ent._IKBlendState = ent._IKBlendState or { pos = {}, ang = {} }
        return ent._IKBlendState
    end
    local function GetCurrentBonePosition(ent, bone)
        if bone == nil then return Vector() end
        return Vector(ent:GetManipulateBonePosition(bone) or Vector())
    end
    local function GetCurrentBoneAngles(ent, bone)
        if bone == nil then return Angle() end
        return Angle(ent:GetManipulateBoneAngles(bone) or Angle())
    end
    local NEAR_EPS_VEC = 0.01; local NEAR_EPS_ANG = 0.05
    local STRIP_POS_EPS = 0.1; local STRIP_ANG_EPS = 0.15
    local function VecNearEps(a, b, eps)
        return math.abs(a.x - b.x) <= eps and math.abs(a.y - b.y) <= eps and math.abs(a.z - b.z) <= eps
    end
    local function AngNearEps(a, b, eps)
        return math.abs(math.AngleDifference(a.p, b.p)) <= eps
            and math.abs(math.AngleDifference(a.y, b.y)) <= eps
            and math.abs(math.AngleDifference(a.r, b.r)) <= eps
    end
    local function ApplyBlendedBonePosition(ent, bone, offset)
        if bone == nil then return end
        local state = GetIKBlendState(ent)
        local entry = state.pos[bone]
        if not entry then entry = { applied = Vector(), final = nil }; state.pos[bone] = entry end
        local current = GetCurrentBonePosition(ent, bone)
        local base = current
        if entry.final and VecNearEps(current, entry.final, NEAR_EPS_VEC) then base = current - entry.applied end
        local final = base + offset
        ent:ManipulateBonePosition(bone, final)
        entry.applied = Vector(offset); entry.final = Vector(final)
    end
    local function ApplyBlendedBoneAngles(ent, bone, offset)
        if bone == nil then return end
        local state = GetIKBlendState(ent)
        local entry = state.ang[bone]
        if not entry then entry = { applied = Angle(), final = nil }; state.ang[bone] = entry end
        local current = GetCurrentBoneAngles(ent, bone)
        local base = current
        if entry.final and AngNearEps(current, entry.final, NEAR_EPS_ANG) then
            base = Angle(current.p - entry.applied.p, current.y - entry.applied.y, current.r - entry.applied.r)
        end
        local final = Angle(base.p + offset.p, base.y + offset.y, base.r + offset.r)
        ent:ManipulateBoneAngles(bone, final)
        entry.applied = Angle(offset); entry.final = Angle(final)
    end

    -- ============================================================
    -- SURFACE CLASSIFICATION
    -- ============================================================
    local function ClassifySurface(trace)
        if trace.HitWorld then return "world", true, NULL end
        local e = trace.Entity
        if not IsValid(e) then return "none", false, NULL end
        if e:IsPlayer() then return "player", false, e end
        if e:IsRagdoll() then return "ragdoll", true, e end
        local cls = e:GetClass()
        if string.StartWith(cls, "prop_") or cls == "func_physbox" then return "prop", true, e end
        return "other", false, e
    end

    -- ============================================================
    -- GROUND SAMPLING
    -- ============================================================
    local function TraceSample(ent, startPos, groundDist)
        local soleOffset = GetIKParam("sole_offset")
        local endPos = startPos - Vector(0, 0, groundDist)
        local trace = util.TraceHull({
            start = startPos, endpos = endPos,
            mins = Vector(-2, -2, 0), maxs = Vector(2, 2, 4),
            mask = MASK_PLAYERSOLID,
            filter = function(e) return e ~= ent and not e:IsPlayer() end,
        })
        if trace.Hit and not IsWalkable(trace.HitNormal) then
            local fallback = util.TraceLine({
                start = startPos, endpos = endPos,
                filter = function(e) return e ~= ent and not e:IsPlayer() end,
            })
            if fallback.Hit and IsWalkable(fallback.HitNormal) then trace = fallback else trace.Hit = false end
        end
        if trace.Hit then
            local normal = trace.HitNormal or vector_up
            local hitPos = trace.HitPos + normal * soleOffset
            if not (isvector(hitPos) and hitPos.x == hitPos.x and hitPos.y == hitPos.y and hitPos.z == hitPos.z) then
                return { hit = false, hitPos = endPos, normal = vector_up, distance = groundDist, startPos = startPos }
            end
            local sType, sAllowed, sEnt = ClassifySurface(trace)
            local sSpeed = IsValid(sEnt) and sEnt.GetVelocity and sEnt:GetVelocity():Length() or 0
            local maxSurfSpeed = GetIKParam("moving_surface_max_speed")
            return {
                hit = true, hitPos = hitPos, normal = normal,
                distance = math.max(startPos.z - hitPos.z, 0), startPos = startPos,
                surfaceType = sType, surfaceAllowed = sAllowed,
                surfaceStable = sType == "world" or (sAllowed and sSpeed <= maxSurfSpeed),
                surfaceSpeed = sSpeed, hitWorld = trace.HitWorld, entity = sEnt,
            }
        end
        return {
            hit = false, hitPos = endPos, normal = vector_up, distance = groundDist, startPos = startPos,
            surfaceType = "none", surfaceAllowed = false, surfaceStable = false,
            surfaceSpeed = 0, hitWorld = false, entity = NULL,
        }
    end
    local function SampleFoot(ent, footPos, footAng, traceStartZ, groundDist, isLeft)
        local fwd = footAng:Forward(); fwd.z = 0
        if fwd:LengthSqr() < 0.001 then fwd = Vector(1, 0, 0) else fwd:Normalize() end
        local right = footAng:Right(); right.z = 0
        if right:LengthSqr() < 0.001 then right = Vector(0, 1, 0) else right:Normalize() end
        local sideSign = isLeft and -1 or 1; local outer = right * (2.5 * sideSign); local inner = -outer
        local base = Vector(footPos.x, footPos.y, traceStartZ)
        local offsets = {
            center = Vector(), toe = fwd * 5.5, heel = -fwd * 3.5,
            left = -right * 2.25, right = right * 2.25,
            toeInner = fwd * 4 + inner * 0.75, toeOuter = fwd * 4 + outer * 0.75,
            outer = outer, inner = inner,
        }
        local samples = {}
        for name, offset in pairs(offsets) do samples[name] = TraceSample(ent, base + offset, groundDist) end
        return samples
    end
    local function ResolveContact(samples, fallbackPos, fallbackNormal)
        local highestHitZ = -math.huge
        for _, s in pairs(samples) do
            if s.hit and IsWalkable(s.normal) and s.hitPos.z > highestHitZ then highestHitZ = s.hitPos.z end
        end
        local clusterFloor = highestHitZ - CLUSTER_TOLERANCE
        local totalWeight, hitCount = 0, 0
        local posSum, normalSum = Vector(), Vector()
        local distSum = 0
        local surfaceWeights = {}
        local bestEntity, bestEntityWeight = NULL, 0
        local stableWeight = 0
        for name, s in pairs(samples) do
            if s.hit and IsWalkable(s.normal) and s.hitPos.z >= clusterFloor then
                local w = SAMPLE_WEIGHTS[name] or 1
                totalWeight = totalWeight + w; hitCount = hitCount + 1
                posSum = posSum + s.hitPos * w; normalSum = normalSum + s.normal * w; distSum = distSum + s.distance * w
                local st = s.surfaceType or "none"; surfaceWeights[st] = (surfaceWeights[st] or 0) + w
                if s.surfaceStable then stableWeight = stableWeight + w end
                if IsValid(s.entity) and w > bestEntityWeight then bestEntity = s.entity; bestEntityWeight = w end
            end
        end
        local pos, normal, dist = fallbackPos, fallbackNormal or vector_up, 0
        if totalWeight > 0 then
            pos = posSum / totalWeight; normal = normalSum / totalWeight
            if normal:LengthSqr() < 0.001 then normal = vector_up else normal:Normalize() end
            dist = distSum / totalWeight
            if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then pos = fallbackPos; hitCount = 0 end
            if normal.x ~= normal.x or normal.y ~= normal.y or normal.z ~= normal.z then normal = vector_up end
        end
        local dominantSurface = "none"; local dominantWeight = 0
        for st, w in pairs(surfaceWeights) do if w > dominantWeight then dominantSurface = st; dominantWeight = w end end
        return {
            hasHit = hitCount > 0, hitCount = hitCount, position = Vector(pos), normal = Vector(normal),
            supportDistance = dist, samples = samples,
            surfaceType = dominantSurface,
            surfaceStable = stableWeight >= math.max(totalWeight * 0.5, 1),
            surfaceEntity = bestEntity, surfaceFromWorld = dominantSurface == "world",
        }
    end
    local function GetStepSignal(contact, legLength)
        if not contact or not contact.hasHit then return { confidence = 0, edge = 0, toeDelta = 0, heelDelta = 0 } end
        local sm = contact.samples
        if not sm then return { confidence = 0, edge = 0, toeDelta = 0, heelDelta = 0 } end
        local center, toe, heel = sm.center, sm.toe, sm.heel
        if not center or not toe or not heel or not center.hit or not toe.hit or not heel.hit then
            return { confidence = 0, edge = 0, toeDelta = 0, heelDelta = 0 }
        end
        local toeDelta = toe.hitPos.z - center.hitPos.z
        local heelDelta = heel.hitPos.z - center.hitPos.z
        local edge = math.max(math.abs(toeDelta), math.abs(heelDelta), math.abs(toeDelta - heelDelta))
        local minStep = math.max(legLength * 0.11, 4)
        local confidence = math.Clamp((edge - minStep * 0.35) / math.max(minStep, 0.5), 0, 1)
        if contact.surfaceType == "world" then confidence = confidence * 1.05
        elseif contact.surfaceType == "prop" or contact.surfaceType == "ragdoll" then confidence = confidence * 0.92
        else confidence = confidence * 0.75 end
        if not contact.surfaceStable then confidence = confidence * 0.45 end
        return { confidence = math.Clamp(confidence, 0, 1), edge = edge, toeDelta = toeDelta, heelDelta = heelDelta }
    end
    local function BuildTerrainHint(lContact, rContact, legLength)
        local lSig = GetStepSignal(lContact, legLength)
        local rSig = GetStepSignal(rContact, legLength)
        local counts = { world = 0, prop = 0, ragdoll = 0, other = 0 }
        for _, c in ipairs({ lContact, rContact }) do
            if c and c.hasHit then
                local st = c.surfaceType or "none"
                if st == "world" then counts.world = counts.world + 1
                elseif st == "prop" then counts.prop = counts.prop + 1
                elseif st == "ragdoll" then counts.ragdoll = counts.ragdoll + 1
                else counts.other = counts.other + 1 end
            end
        end
        local bestSurface, bestCount = "none", -1
        for st, cnt in pairs(counts) do if cnt > bestCount then bestSurface = st; bestCount = cnt end end
        local stableCount = (lContact and lContact.surfaceStable and 1 or 0) + (rContact and rContact.surfaceStable and 1 or 0)
        return {
            surfaceType = bestSurface, stable = stableCount > 0,
            leftSignal = lSig, rightSignal = rSig,
            edgeConfidence = math.max(lSig.confidence, rSig.confidence),
            edgeMagnitude = math.max(lSig.edge, rSig.edge),
        }
    end
    local function ValidateContact(contact, samples, footBoneZ, tolerance)
        tolerance = tolerance or 0.5
        local result = { isValid = true, penetrationCount = 0, correctionZ = 0, highestValidZ = -math.huge, lowestHitZ = math.huge, invalidReason = nil, normalVariance = 0 }
        if not contact.hasHit then result.isValid = false; result.invalidReason = "no_hit"; return result end
        local soleOffset = GetIKParam("sole_offset")
        local expectedSoleZ = footBoneZ - soleOffset
        local totalHits, belowSole, penetrating = 0, 0, 0
        local normals = {}
        for _, s in pairs(samples) do
            if not s.hit then continue end
            totalHits = totalHits + 1; normals[#normals + 1] = s.normal
            local rawZ = s.hitPos.z - soleOffset
            if rawZ > footBoneZ + tolerance then penetrating = penetrating + 1 end
            if rawZ < expectedSoleZ - tolerance * 2 then belowSole = belowSole + 1 end
            if rawZ <= footBoneZ + tolerance and s.hitPos.z > result.highestValidZ then result.highestValidZ = s.hitPos.z end
            if s.hitPos.z < result.lowestHitZ then result.lowestHitZ = s.hitPos.z end
        end
        result.penetrationCount = penetrating
        if totalHits > 0 and penetrating / totalHits > 0.4 then
            result.isValid = false; result.invalidReason = "penetrating"
            if result.highestValidZ > -math.huge then result.correctionZ = result.highestValidZ + soleOffset - footBoneZ
            else result.correctionZ = contact.position.z - footBoneZ end
        end
        if totalHits > 0 and belowSole / totalHits > 0.6 then result.invalidReason = result.invalidReason or "below_sole" end
        if #normals >= 3 then
            local avgNormal = Vector()
            for _, n in ipairs(normals) do avgNormal:Add(n) end; avgNormal:Div(#normals)
            if avgNormal:LengthSqr() > 0.001 then avgNormal:Normalize() end
            local variance = 0
            for _, n in ipairs(normals) do variance = variance + (1 - n:Dot(avgNormal)) end
            result.normalVariance = variance / #normals
            if result.normalVariance > 0.35 then result.invalidReason = result.invalidReason or "inconsistent_normals" end
        end
        if contact.normal.z < WALKABLE_Z then result.isValid = false; result.invalidReason = result.invalidReason or "steep_surface" end
        return result
    end
    local function PredictLanding(ent, fromPos, moveDir, lookDist, upClear, groundDist)
        local searchTop = Vector(fromPos.x + moveDir.x * lookDist, fromPos.y + moveDir.y * lookDist, fromPos.z + upClear)
        local searchBot = Vector(searchTop.x, searchTop.y, fromPos.z - groundDist)
        local trace = util.TraceHull({
            start = searchTop, endpos = searchBot,
            mins = Vector(-2, -2, 0), maxs = Vector(2, 2, 4), mask = MASK_PLAYERSOLID,
            filter = function(e) return e ~= ent and not e:IsPlayer() end,
        })
        if trace.Hit and IsWalkable(trace.HitNormal) then
            local soleOff = GetIKParam("sole_offset")
            local landPos = trace.HitPos + (trace.HitNormal or vector_up) * soleOff
            if landPos.x == landPos.x and landPos.y == landPos.y and landPos.z == landPos.z then return landPos end
        end
        return nil
    end

    -- ============================================================
    -- MODEL ANALYSIS
    -- ============================================================
    local ModelAnalysisCache = {}
    local function InvalidateModelCache(model)
        if model then ModelAnalysisCache[model] = nil else ModelAnalysisCache = {} end
    end
    local function MeasureModel(ent)
        if not IsValid(ent) then return nil end
        local model = ent:GetModel()
        if not model or model == "" then return nil end
        local cached = ModelAnalysisCache[model]
        if cached then return cached.suggested, nil, cached.info end
        local lF = ent:LookupBone("ValveBiped.Bip01_L_Foot")
        local rF = ent:LookupBone("ValveBiped.Bip01_R_Foot")
        local lC = ent:LookupBone("ValveBiped.Bip01_L_Calf")
        local rC = ent:LookupBone("ValveBiped.Bip01_R_Calf")
        local lT = ent:LookupBone("ValveBiped.Bip01_L_Thigh")
        local rT = ent:LookupBone("ValveBiped.Bip01_R_Thigh")
        if not lF or not rF or not lC or not rC or not lT or not rT then return nil end
        ent:SetupBones()
        local function BPA(bone)
            if not bone then return nil, nil end
            local mat = ent:GetBoneMatrix(bone)
            if mat then return mat:GetTranslation(), mat:GetAngles() end
            return ent:GetBonePosition(bone)
        end
        local lTPos, lTAng = BPA(lT); local lCPos = BPA(lC); local lFPos, lFAng = BPA(lF)
        local rTPos, rTAng = BPA(rT); local rCPos = BPA(rC); local rFPos, rFAng = BPA(rF)
        if not lTPos or not lCPos or not lFPos or not rTPos or not rCPos or not rFPos then return nil end
        local lUL = lTPos:Distance(lCPos); local lLL = lCPos:Distance(lFPos)
        local rUL = rTPos:Distance(rCPos); local rLL = rCPos:Distance(rFPos)
        local legLength = (lUL + lLL + rUL + rLL) * 0.5
        local meshInfo = util.GetModelMeshes(model)
        local meshBottomZ, soleExtra = 0, 0
        if meshInfo then
            local lowestZ = math.huge
            for _, mg in ipairs(meshInfo) do
                if not mg.triangles then continue end
                for _, vert in ipairs(mg.triangles) do
                    if vert.pos and vert.pos.z < lowestZ then lowestZ = vert.pos.z end
                end
            end
            if lowestZ < math.huge then meshBottomZ = lowestZ end
            local entZ = ent:GetPos().z
            local footH = ((lFPos.z - entZ) + (rFPos.z - entZ)) * 0.5
            local groundGap = math.Clamp(math.max(meshBottomZ, 0), 0, footH * 0.8)
            local belowOrigin = math.max(0, -meshBottomZ)
            soleExtra = math.Clamp(belowOrigin * 0.35 + groundGap * 0.5, 0, 2)
        end
        local suggested = {
            leg_length = math.Round(legLength, 0),
            sole_offset = math.Round(soleExtra, 2),
            extra_body_drop = math.Round(math.max(0.3, 0.3 + (meshBottomZ or 0) / math.max(legLength / 45, 0.1)), 1),
            extra_body_drop_uneven = math.Round(math.max(1.2, 1.2 + (meshBottomZ or 0) / math.max(legLength / 45, 0.1)), 1),
            max_body_drop = math.Round(math.Clamp(legLength * 0.95, 42, 80), 0),
        }
        local info = { model = model, legLength = legLength, soleOffset = soleExtra }
        ModelAnalysisCache[model] = { suggested = suggested, info = info }
        return suggested, nil, info
    end
    local function AutoApplyModelSettings(ent)
        local suggested, _, info = MeasureModel(ent)
        if not suggested then return end
        for key, value in pairs(suggested) do
            local entry = IK_CVARS[key]
            if entry then
                RunConsoleCommand(entry.c:GetName(), tostring(value))
            end
        end
    end

    -- ============================================================
    -- STATE MANAGEMENT
    -- ============================================================
    local function EnsureFootState(cont, side)
        cont.legs = cont.legs or {}
        cont.legs[side] = cont.legs[side] or {
            planted = false, lockPos = nil, lastRawPos = nil, lastTargetPos = nil,
            footSpeed = 0, released = false, lockAge = 0,
            proc = { phase = "planted", plantPos = nil, swingStart = nil, swingTarget = nil, swingT = 0, liftH = 0, blendT = 0 },
        }
        return cont.legs[side]
    end
    local PROC_DEFAULT = function()
        return { phase = "planted", plantPos = nil, swingStart = nil, swingTarget = nil, swingT = 0, liftH = 0, blendT = 0 }
    end
    local function GetRuntimeState(ent)
        if not ent._IKRuntimeState then
            ent._IKRuntimeState = {
                idle = { active = false, candidateTime = 0 },
                legs = {}, bodyDrop = nil,
                stairs = { sequence = 0, lastStepTime = 0, confidence = 0, upHeight = 0, downHeight = 0, eventHeight = 0, mode = false, prevLeftReq = 0, prevRightReq = 0 },
                crouch = { crouching = false, transitionTime = 0, inTransition = false },
            }
        end
        EnsureFootState(ent._IKRuntimeState, "left")
        EnsureFootState(ent._IKRuntimeState, "right")
        if not ent._IKRuntimeState.crouch then ent._IKRuntimeState.crouch = { crouching = false, transitionTime = 0, inTransition = false } end
        if not ent._IKRuntimeState.stairs then ent._IKRuntimeState.stairs = { sequence = 0, lastStepTime = 0, confidence = 0, upHeight = 0, downHeight = 0, eventHeight = 0, mode = false, prevLeftReq = 0, prevRightReq = 0 } end
        return ent._IKRuntimeState
    end
    local function StateSoftRecover(ent)
        local state = GetRuntimeState(ent)
        state.bodyDrop = nil; state.idle.active = false; state.idle.candidateTime = 0
        for _, side in ipairs({"left", "right"}) do
            local leg = EnsureFootState(state, side)
            leg.planted = false; leg.lockPos = nil; leg.lastRawPos = nil; leg.lastTargetPos = nil
            leg.footSpeed = 0; leg.released = true; leg.lockAge = 0; leg.proc = PROC_DEFAULT()
        end
        state.stairs = { sequence = 0, lastStepTime = 0, confidence = 0, upHeight = 0, downHeight = 0, eventHeight = 0, mode = false, prevLeftReq = 0, prevRightReq = 0 }
    end
    local function UpdateCrouch(state, isCrouching)
        local crouch = state.crouch
        if crouch.crouching ~= isCrouching then
            crouch.crouching = isCrouching; crouch.transitionTime = 0; crouch.inTransition = true
            for _, side in ipairs({"left", "right"}) do
                local leg = state.legs[side]
                if leg then leg.planted = false; leg.lockPos = nil; leg.lastRawPos = nil end
            end
            state.idle.active = false; state.idle.candidateTime = 0
        end
        if crouch.inTransition then
            crouch.transitionTime = crouch.transitionTime + FrameTime()
            if crouch.transitionTime >= CROUCH_BLEND_TIME then crouch.inTransition = false end
        end
        return crouch
    end
    local function UpdateIdle(state, onGround, vel2D, vertVel, idleVelThresh, lRaw, rRaw)
        local idle = state.idle
        local isCandidate = onGround and vel2D <= idleVelThresh and math.abs(vertVel) <= idleVelThresh * 0.5
        if isCandidate then idle.candidateTime = idle.candidateTime + FrameTime()
        else idle.candidateTime = 0; idle.active = false end
        if isCandidate and idle.candidateTime >= IDLE_ACQUIRE_DELAY then
            idle.active = true; idle.leftRaw = Vector(lRaw); idle.rightRaw = Vector(rRaw)
        end
        return idle, isCandidate
    end
    local function MeasureFootSpeed(footState, rawPos, dt)
        if dt <= 0 then footState.footSpeed = 0
        elseif footState.lastRawPos and IsFiniteVector(rawPos) and IsFiniteVector(footState.lastRawPos) then
            footState.footSpeed = rawPos:Distance(footState.lastRawPos) / math.max(dt, 1/300)
        else footState.footSpeed = 0 end
        if IsFiniteVector(rawPos) then footState.lastRawPos = Vector(rawPos) end
        return footState.footSpeed
    end
    local function UpdateFoot(footState, data)
        footState.released = false
        if data.contact.hasHit and not IsFiniteVector(data.contact.position) then data.contact.hasHit = false end
        if not data.onGround then footState.planted = false; footState.lockPos = nil end
        if footState.lockPos then
            local lockDist = data.rawFootPos:Distance(footState.lockPos)
            if lockDist > math.max(40, data.lockStrength * 25) then footState.planted = false; footState.lockPos = nil; footState.released = true end
        end
        local acquireDist = math.max(4, 8 * data.lockStrength)
        local releaseDist = math.max(acquireDist * 1.3, 6 + data.lockStrength * 6)
        local stairReleaseMul = math.max(tonumber(data.stairReleaseMul) or 1, 1)
        local releaseSpeed = math.max(data.releaseSpeed, 5)
        local stairMode = data.stairMode and (data.stairConfidence or 0) >= 0.2
        if stairMode then
            if data.isSupportFoot then
                releaseDist = releaseDist * math.max(1.05, stairReleaseMul * 0.9)
                acquireDist = acquireDist * math.Clamp(1 + (data.stairConfidence or 0) * 0.2, 1, 1.2)
            else
                releaseDist = releaseDist * 0.82; acquireDist = acquireDist * 0.9; releaseSpeed = releaseSpeed * 0.82
            end
        end
        local shouldAcquire = data.contact.hasHit and data.onGround and (
            data.idleActive
            or (data.footSpeed <= releaseSpeed * 0.55 and data.rawFootPos:Distance(data.contact.position) <= acquireDist)
            or (data.isSupportFoot and data.rawFootPos:Distance(data.contact.position) <= acquireDist * 1.2)
        )
        if footState.lockPos then
            footState.lockAge = (footState.lockAge or 0) + FrameTime()
            local distToLock = data.rawFootPos:Distance(footState.lockPos)
            local wantsRelease = data.footSpeed > releaseSpeed and distToLock > releaseDist * 0.5
            local stairHardLimit = stairMode and (data.isSupportFoot and releaseDist * 0.85 or releaseDist * 0.55) or math.huge
            if not data.idleActive and (wantsRelease or distToLock > releaseDist or distToLock > stairHardLimit) then
                footState.planted = false; footState.lockPos = nil; footState.released = true
            end
        end
        if not footState.lockPos and shouldAcquire then
            footState.lockPos = Vector(data.contact.position); footState.planted = true; footState.lockAge = 0
        elseif footState.lockPos then footState.planted = true end
        if footState.lockPos and (footState.lockAge or 0) > 10 then
            footState.planted = false; footState.lockPos = nil; footState.released = true; footState.lockAge = 0
        end
        if data.idleActive and data.contact.hasHit then
            if not footState.lockPos then footState.lockPos = Vector(data.contact.position) end
            footState.planted = true
        end
        local desiredPos
        if footState.lockPos then desiredPos = Vector(footState.lockPos)
        elseif data.contact.hasHit then desiredPos = Vector(data.contact.position)
        else desiredPos = Vector(data.rawFootPos) end
        if not IsFiniteVector(desiredPos) then desiredPos = IsFiniteVector(data.rawFootPos) and Vector(data.rawFootPos) or Vector() end
        footState.lastTargetPos = Vector(desiredPos)
        return { planted = footState.planted and footState.lockPos ~= nil, lockPos = footState.lockPos and Vector(footState.lockPos) or nil, targetPos = desiredPos, footSpeed = footState.footSpeed, released = footState.released }
    end
    local function UpdateStairSequence(state, stairData)
        local stairs = state.stairs
        local now = CurTime()
        local window = math.max(tonumber(stairData.sequenceWindow) or 0.33, 0.12)
        local stepUp = math.max(stairData.leftRise or 0, stairData.rightRise or 0)
        local stepDown = math.max(stairData.leftDrop or 0, stairData.rightDrop or 0)
        local eventHeight = math.max(stepUp, stepDown, (stairData.heightDiff or 0) * 0.75)
        if eventHeight > 0.2 and stairData.eligible then
            if now - (stairs.lastStepTime or 0) <= window then stairs.sequence = math.min((stairs.sequence or 0) + 1, 8)
            else stairs.sequence = 1 end
            stairs.lastStepTime = now
        else stairs.sequence = math.max((stairs.sequence or 0) - FrameTime() * 4, 0) end
        local confBase = stairData.edgeConfidence or 0
        local asymSignal = math.Clamp((stairData.heightDiff or 0) / math.max(tonumber(stairData.stepMax) or 24, 1), 0, 1)
        local seqBonus = math.Clamp((stairs.sequence or 0) / 3, 0, 1)
        local confidence = math.Clamp(confBase * 0.55 + asymSignal * 0.5 + seqBonus * 0.4, 0, 1)
        if not stairData.surfaceStable then confidence = confidence * 0.5 end
        stairs.confidence = confidence; stairs.upHeight = stepUp; stairs.downHeight = stepDown
        stairs.eventHeight = eventHeight; stairs.mode = stairData.eligible and confidence >= 0.4
        return { mode = stairs.mode, confidence = confidence, sequence = stairs.sequence, upHeight = stepUp, downHeight = stepDown, eventHeight = eventHeight }
    end
    local function UpdateStepperFoot(footState, otherFootState, data)
        local proc = footState.proc
        if not proc then footState.proc = PROC_DEFAULT(); proc = footState.proc end
        local fadeRate = data.stairMode and 6 or -5
        proc.blendT = math.Clamp((proc.blendT or 0) + data.dt * fadeRate, 0, 1)
        if not proc.plantPos then proc.plantPos = data.currentLock and Vector(data.currentLock) or Vector(data.rawFootPos); proc.phase = "planted"; proc.swingT = 0 end
        if data.stairMode then
            local otherProc = otherFootState and otherFootState.proc
            local otherSwinging = otherProc and otherProc.phase == "swinging"
            if proc.phase == "planted" then
                local behind = (data.playerPos - proc.plantPos):Dot(data.moveDir)
                if not otherSwinging and behind >= data.strideLen * 0.45 and data.vel2D > 5 and data.swingTarget then
                    proc.phase = "swinging"; proc.swingStart = Vector(proc.plantPos); proc.swingT = 0
                    proc.liftH = data.liftHeight; proc.swingTarget = Vector(data.swingTarget)
                end
            end
            if proc.phase == "swinging" then
                local swingRate = math.max(data.vel2D, 8) / math.max(data.strideLen, 10)
                proc.swingT = math.min(proc.swingT + data.dt * swingRate, 1.0)
                if proc.swingT >= 1.0 then
                    proc.phase = "planted"; proc.plantPos = proc.swingTarget and Vector(proc.swingTarget) or Vector(data.rawFootPos); proc.swingStart = nil
                end
            end
        else
            if proc.blendT <= 0 then proc.plantPos = nil; proc.phase = "planted"; proc.swingT = 0 end
        end
        local procPos
        if proc.phase == "swinging" and proc.swingStart and proc.swingTarget then
            local t = proc.swingT
            local x = proc.swingStart.x + (proc.swingTarget.x - proc.swingStart.x) * t
            local y = proc.swingStart.y + (proc.swingTarget.y - proc.swingStart.y) * t
            local baseZ = proc.swingStart.z + (proc.swingTarget.z - proc.swingStart.z) * t
            procPos = Vector(x, y, baseZ + math.sin(t * math.pi) * proc.liftH)
        elseif proc.plantPos then procPos = Vector(proc.plantPos)
        else return nil end
        if not (isvector(procPos) and procPos.x == procPos.x) then return nil end
        if proc.blendT < 1 then
            local raw = data.rawFootPos
            return Vector(raw.x + (procPos.x - raw.x) * proc.blendT, raw.y + (procPos.y - raw.y) * proc.blendT, raw.z + (procPos.z - raw.z) * proc.blendT)
        end
        return procPos
    end

    -- ============================================================
    -- BONE CACHE
    -- ============================================================
    local function GetIKBones(ent)
        local model = ent:GetModel()
        local bones = ent._IKBones
        if bones and bones.model == model then return bones end
        ent._IKBlendState = nil
        bones = {
            model = model,
            lFoot = ent:LookupBone("ValveBiped.Bip01_L_Foot"),
            rFoot = ent:LookupBone("ValveBiped.Bip01_R_Foot"),
            lCalf = ent:LookupBone("ValveBiped.Bip01_L_Calf"),
            rCalf = ent:LookupBone("ValveBiped.Bip01_R_Calf"),
            lThigh = ent:LookupBone("ValveBiped.Bip01_L_Thigh"),
            rThigh = ent:LookupBone("ValveBiped.Bip01_R_Thigh"),
        }
        ent._IKBones = bones; return bones
    end

    -- ============================================================
    -- BUILD SKELETON
    -- ============================================================
    local function BuildSkeleton(ent, bones)
        local lTP = GetBoneWorldTransform(ent, bones.lThigh)
        local lCP = GetBoneWorldTransform(ent, bones.lCalf)
        local lFP, lFA = GetBoneWorldTransform(ent, bones.lFoot)
        local rTP = GetBoneWorldTransform(ent, bones.rThigh)
        local rCP = GetBoneWorldTransform(ent, bones.rCalf)
        local rFP, rFA = GetBoneWorldTransform(ent, bones.rFoot)
        if not lTP or not lCP or not lFP or not rTP or not rCP or not rFP then return nil end
        if ent._IKMeasuredModel ~= (bones and bones.model) then
            local measured = ((lTP:Distance(lCP) + lCP:Distance(lFP)) + (rTP:Distance(rCP) + rCP:Distance(rFP))) * 0.5
            if measured > 20 then ent._IKMeasuredLegLength = measured; ent._IKMeasuredModel = bones and bones.model end
        end
        return {
            measuredLegLength = ent._IKMeasuredLegLength or GetIKParam("leg_length"),
            left = { footPos = lFP, footAng = lFA, calfPos = lCP, thighPos = lTP },
            right = { footPos = rFP, footAng = rFA, calfPos = rCP, thighPos = rTP },
        }
    end

    -- ============================================================
    -- APPLY STATE
    -- ============================================================
    local function EnsureApplyState(ent)
        if not ent._IKApplyState then
            local s = { basePos = Vector(), basePosVel = Vector(), baseAng = Angle(), baseAngVel = Angle() }
            for _, name in ipairs(SPRING_FIELDS) do s[name] = Angle(); s[name .. "Vel"] = Angle() end
            ent._IKApplyState = s
        end
        return ent._IKApplyState
    end

    -- ============================================================
    -- STRIP / APPLY
    -- ============================================================
    local function StripIK(ent, bones)
        local bs = GetIKBlendState(ent)
        local pe = bs.pos[0]
        if pe and pe.applied and pe.final then
            local cur = GetCurrentBonePosition(ent, 0)
            if VecNearEps(cur, pe.final, STRIP_POS_EPS) then ent:ManipulateBonePosition(0, cur - pe.applied) end
        end
        local allB = {0, bones.lThigh, bones.rThigh, bones.lCalf, bones.rCalf, bones.lFoot, bones.rFoot}
        for _, bone in ipairs(allB) do
            if bone then
                local ae = bs.ang[bone]
                if ae and ae.applied and ae.final then
                    local cur = GetCurrentBoneAngles(ent, bone)
                    if AngNearEps(cur, ae.final, STRIP_ANG_EPS) then
                        ent:ManipulateBoneAngles(bone, Angle(cur.p - ae.applied.p, cur.y - ae.applied.y, cur.r - ae.applied.r))
                    end
                end
            end
        end
    end
    local function ApplyResult(ent, bones, result)
        local s = EnsureApplyState(ent)
        local dt = math.Clamp(FrameTime(), 1 / 300, 1 / 20)
        local posST = math.max(0.02, 0.28 / math.max(GetIKParam("smoothing"), 1))
        local rotST = math.max(0.02, 0.28 / math.max(GetIKParam("rotation_smoothing"), 1))
        local targets = {
            leftThigh = result.left.thigh, leftCalf = result.left.calf, leftFoot = result.left.foot,
            rightThigh = result.right.thigh, rightCalf = result.right.calf, rightFoot = result.right.foot,
        }
        s.basePos, s.basePosVel = SpringVector(s.basePos, s.basePosVel, result.basePos, posST, dt)
        s.baseAng, s.baseAngVel = SpringAngle(s.baseAng, s.baseAngVel, result.baseAng, rotST, dt)
        for _, name in ipairs(SPRING_FIELDS) do s[name], s[name .. "Vel"] = SpringAngle(s[name], s[name .. "Vel"], targets[name], rotST, dt) end
        if not IsFiniteVector(s.basePos) or not IsFiniteNumber(s.baseAng.p) then ent._IKApplyState = nil; s = EnsureApplyState(ent) end
        ApplyBlendedBonePosition(ent, 0, s.basePos); ApplyBlendedBoneAngles(ent, 0, s.baseAng)
        ApplyBlendedBoneAngles(ent, bones.lThigh, s.leftThigh); ApplyBlendedBoneAngles(ent, bones.rThigh, s.rightThigh)
        ApplyBlendedBoneAngles(ent, bones.lCalf, s.leftCalf); ApplyBlendedBoneAngles(ent, bones.rCalf, s.rightCalf)
        ApplyBlendedBoneAngles(ent, bones.lFoot, s.leftFoot); ApplyBlendedBoneAngles(ent, bones.rFoot, s.rightFoot)
    end
    local function ResetPlayer(ent, bones)
        bones = bones or GetIKBones(ent)
        ApplyBlendedBonePosition(ent, 0, Vector()); ApplyBlendedBoneAngles(ent, 0, Angle())
        ApplyBlendedBoneAngles(ent, bones.lThigh, Angle()); ApplyBlendedBoneAngles(ent, bones.rThigh, Angle())
        ApplyBlendedBoneAngles(ent, bones.lCalf, Angle()); ApplyBlendedBoneAngles(ent, bones.rCalf, Angle())
        ApplyBlendedBoneAngles(ent, bones.lFoot, Angle()); ApplyBlendedBoneAngles(ent, bones.rFoot, Angle())
        ent._IKApplyState = nil; GetRuntimeState(ent).bodyDrop = nil
    end
    local function HardResetPlayer(ent)
        local bones = GetIKBones(ent)
        local allB = {0, bones.lThigh, bones.rThigh, bones.lCalf, bones.rCalf, bones.lFoot, bones.rFoot}
        for _, bone in ipairs(allB) do if bone then ent:ManipulateBonePosition(bone, Vector()); ent:ManipulateBoneAngles(bone, Angle()) end end
        ent._IKApplyState = nil; ent._IKRuntimeState = nil; ent._IKBlendState = nil
        if IsValid(ent) then ent:SetupBones() end
    end

    -- ============================================================
    -- CONTROLLER CORE
    -- ============================================================
    local DynSoleState = {}
    local function GetDynSole(ent)
        local id = ent:EntIndex()
        if not DynSoleState[id] then DynSoleState[id] = { correction = 0 } end
        return DynSoleState[id]
    end
    local function ResetDynSole(ent)
        DynSoleState[ent:EntIndex()] = nil
    end
    local function DetermineSupportSide(lContact, rContact, lState, rState)
        if lContact.hasHit and rContact.hasHit then
            local zd = lContact.position.z - rContact.position.z
            if math.abs(zd) > 0.5 then return zd < 0 and "left" or "right" end
        end
        if lState.planted and not rState.planted then return "left" end
        if rState.planted and not lState.planted then return "right" end
        return lContact.supportDistance >= rContact.supportDistance and "left" or "right"
    end
    local function ComputeFootRotation(samples, scale)
        if scale <= 0.01 then return Angle() end
        local toe, heel = samples.toe, samples.heel
        local sL, sR = samples.left, samples.right
        local pitch, roll = 0, 0
        if toe and heel and toe.hit and heel.hit then
            local len = math.max(toe.hitPos:Distance(heel.hitPos), 0.01)
            pitch = math.Clamp(-math.deg(math.atan2(toe.hitPos.z - heel.hitPos.z, len)) * scale, -MAX_FOOT_PITCH, MAX_FOOT_PITCH)
        end
        if sL and sR and sL.hit and sR.hit then
            local len = math.max(sR.hitPos:Distance(sL.hitPos), 0.01)
            roll = math.Clamp(math.deg(math.atan2(sR.hitPos.z - sL.hitPos.z, len)) * scale, -MAX_FOOT_ROLL, MAX_FOOT_ROLL)
        end
        return Angle(0, pitch, roll)
    end

    -- ============================================================
    -- CONTROLLER  (full)
    -- ============================================================
    local function CalculateIK(ent, skeleton)
        local legLength = skeleton.measuredLegLength or GetIKParam("leg_length")
        local modelScale = math.Clamp(legLength / REFERENCE_LEG_LENGTH, 0.4, 2.5)
        local groundDist = GetIKParam("ground_distance") * modelScale
        local scaledLegLen = legLength * modelScale
        local traceStartOff = GetIKParam("trace_start_offset") * modelScale
        local extraDrop = GetIKParam("extra_body_drop") * modelScale
        local extraDropUneven = GetIKParam("extra_body_drop_uneven") * modelScale
        local footRotScale = GetIKParam("foot_rotation_scale")
        local idleVelThresh = GetIKParam("idle_velocity")
        local lockStrength = GetIKParam("lock_strength")
        local releaseSpeed = GetIKParam("release_speed")
        local maxBodyDropCVar = GetIKParam("max_body_drop") * modelScale
        local soleOffset = GetIKParam("sole_offset")
        local stepMinH = GetIKParam("stair_step_min_height")
        local stepMaxH = GetIKParam("stair_step_max_height")
        local stepWindow = GetIKParam("stair_sequence_window")
        local stairReleaseMul = GetIKParam("stair_release_multiplier")
        local stairStepMul = GetIKParam("stair_adaptive_maxstep")
        local stabilizeIdle = GetIKParamBool("stabilize_idle")
        local antiClip = GetIKParamBool("anti_clip")
        local dynamicSole = GetIKParamBool("dynamic_sole")

        local state = GetRuntimeState(ent)
        local dt = math.Clamp(FrameTime(), 1 / 300, 1 / 20)
        local vel = ent:GetVelocity()
        local vel2D = vel:Length2D()
        local velZ = vel.z
        local onGround = ent:OnGround()
        local traceStartZ = ent:GetPos().z + traceStartOff

        local isCrouching = IsCrouching(ent)
        local crouch = UpdateCrouch(state, isCrouching)

        local lFoot = state.legs.left; local rFoot = state.legs.right

        -- === PROCEDURAL STEPPER ===
        local prevStairMode = state.stairs and state.stairs.mode or false
        local prevStairConf = state.stairs and state.stairs.confidence or 0
        local lUsePos = skeleton.left.footPos; local rUsePos = skeleton.right.footPos
        if onGround and not crouch.inTransition then
            local prevEventH = math.max((state.stairs and state.stairs.eventHeight or 0) * modelScale, 4)
            local strideLen = math.Clamp(prevEventH * 1.5, scaledLegLen * 0.35, scaledLegLen * 0.65)
            local liftH = math.max(prevEventH * 0.65, 4 * modelScale)
            local moveDir
            if vel2D >= 5 then moveDir = Vector(vel.x / vel2D, vel.y / vel2D, 0)
            else
                moveDir = ent:GetAngles():Forward(); moveDir.z = 0; moveDir:Normalize()
                if moveDir:LengthSqr() < 0.1 then moveDir = Vector(1, 0, 0) end
            end
            local rightDir = Vector(moveDir.y, -moveDir.x, 0)
            local halfWidth = math.max(scaledLegLen * 0.1, 3)
            local playerGround = ent:GetPos()
            local upClear = prevEventH * 2 + 8
            local lBase = Vector(playerGround.x - rightDir.x * halfWidth, playerGround.y - rightDir.y * halfWidth, playerGround.z)
            local rBase = Vector(playerGround.x + rightDir.x * halfWidth, playerGround.y + rightDir.y * halfWidth, playerGround.z)
            local lTarget = PredictLanding(ent, lBase, moveDir, strideLen * 0.9, upClear, groundDist)
            local rTarget = PredictLanding(ent, rBase, moveDir, strideLen * 0.9, upClear, groundDist)
            local sd = { stairMode = prevStairMode and prevStairConf >= 0.4, stairConfidence = prevStairConf,
                playerPos = playerGround, moveDir = moveDir, strideLen = strideLen, liftHeight = liftH, vel2D = vel2D, dt = dt }
            local lProc = UpdateStepperFoot(lFoot, rFoot, {
                stairMode = sd.stairMode, stairConfidence = sd.stairConfidence, playerPos = sd.playerPos,
                moveDir = sd.moveDir, strideLen = sd.strideLen, liftHeight = sd.liftHeight, vel2D = sd.vel2D, dt = sd.dt,
                currentLock = lFoot.lockPos, rawFootPos = skeleton.left.footPos, swingTarget = lTarget,
            })
            local rProc = UpdateStepperFoot(rFoot, lFoot, {
                stairMode = sd.stairMode, stairConfidence = sd.stairConfidence, playerPos = sd.playerPos,
                moveDir = sd.moveDir, strideLen = sd.strideLen, liftHeight = sd.liftHeight, vel2D = sd.vel2D, dt = sd.dt,
                currentLock = rFoot.lockPos, rawFootPos = skeleton.right.footPos, swingTarget = rTarget,
            })
            if lProc then lUsePos = lProc end; if rProc then rUsePos = rProc end
        else
            if lFoot.proc and (lFoot.proc.blendT or 0) > 0 then
                local lp = UpdateStepperFoot(lFoot, rFoot, { stairMode = false, dt = dt, rawFootPos = skeleton.left.footPos, currentLock = lFoot.lockPos, playerPos = ent:GetPos(), moveDir = Vector(1,0,0), strideLen = 20, liftHeight = 8, vel2D = 0 })
                if lp then lUsePos = lp end
            end
            if rFoot.proc and (rFoot.proc.blendT or 0) > 0 then
                local rp = UpdateStepperFoot(rFoot, lFoot, { stairMode = false, dt = dt, rawFootPos = skeleton.right.footPos, currentLock = rFoot.lockPos, playerPos = ent:GetPos(), moveDir = Vector(1,0,0), strideLen = 20, liftHeight = 8, vel2D = 0 })
                if rp then rUsePos = rp end
            end
        end

        local lSamples = SampleFoot(ent, lUsePos, skeleton.left.footAng, traceStartZ, groundDist, true)
        local rSamples = SampleFoot(ent, rUsePos, skeleton.right.footAng, traceStartZ, groundDist, false)
        local lContact = ResolveContact(lSamples, lUsePos, vector_up)
        local rContact = ResolveContact(rSamples, rUsePos, vector_up)
        local terrainHint = BuildTerrainHint(lContact, rContact, scaledLegLen)

        local lValidation = ValidateContact(lContact, lSamples, lUsePos.z, soleOffset)
        local rValidation = ValidateContact(rContact, rSamples, rUsePos.z, soleOffset)

        local idle = UpdateIdle(state, onGround and stabilizeIdle, vel2D, velZ, idleVelThresh, lUsePos, rUsePos)
        local lSpeed = MeasureFootSpeed(lFoot, lUsePos, dt)
        local rSpeed = MeasureFootSpeed(rFoot, rUsePos, dt)

        if antiClip then
            if not lValidation.isValid and lValidation.invalidReason == "penetrating" then lFoot.planted = false; lFoot.lockPos = nil end
            if not rValidation.isValid and rValidation.invalidReason == "penetrating" then rFoot.planted = false; rFoot.lockPos = nil end
        end

        local support = DetermineSupportSide(lContact, rContact, lFoot, rFoot)
        local effectiveOnGround = onGround and not crouch.inTransition

        local lProcSwing = lFoot.proc and lFoot.proc.phase == "swinging"
        local rProcSwing = rFoot.proc and rFoot.proc.phase == "swinging"
        local function ProcContact(c)
            return { hasHit = false, position = c.position, normal = c.normal, supportDistance = c.supportDistance, hitCount = 0, samples = c.samples, surfaceType = c.surfaceType, surfaceStable = c.surfaceStable, surfaceEntity = c.surfaceEntity, surfaceFromWorld = c.surfaceFromWorld }
        end
        local lContactFS = lProcSwing and ProcContact(lContact) or lContact
        local rContactFS = rProcSwing and ProcContact(rContact) or rContact
        local function fd(contact, rawPos, speed, side)
            return { onGround = effectiveOnGround, idleActive = idle.active and not crouch.inTransition, isSupportFoot = support == side,
                contact = contact, rawFootPos = rawPos, footSpeed = speed, lockStrength = lockStrength, releaseSpeed = releaseSpeed,
                stairMode = state.stairs and state.stairs.mode or false, stairConfidence = state.stairs and state.stairs.confidence or 0, stairReleaseMul = stairReleaseMul }
        end
        local lResult = UpdateFoot(lFoot, fd(lContactFS, lUsePos, lSpeed, "left"))
        local rResult = UpdateFoot(rFoot, fd(rContactFS, rUsePos, rSpeed, "right"))

        local bodyDrop, lReqDrop, rReqDrop = 0, 0, 0
        local lKnee, rKnee = 0, 0
        local lFootRot, rFootRot = Angle(), Angle()
        local dynSoleCorr = 0
        local penCorrL, penCorrR = 0, 0

        if onGround then
            local lDist = lContact.hasHit and lContact.supportDistance or traceStartOff
            local rDist = rContact.hasHit and rContact.supportDistance or traceStartOff
            lReqDrop = math.max(lDist - traceStartOff, 0); rReqDrop = math.max(rDist - traceStartOff, 0)

            if antiClip then
                if not lValidation.isValid and lValidation.invalidReason == "penetrating" and lValidation.highestValidZ > -math.huge then
                    lReqDrop = math.max(traceStartZ - lValidation.highestValidZ - traceStartOff, 0)
                end
                if not rValidation.isValid and rValidation.invalidReason == "penetrating" and rValidation.highestValidZ > -math.huge then
                    rReqDrop = math.max(traceStartZ - rValidation.highestValidZ - traceStartOff, 0)
                end
            end

            if dynamicSole then
                local ds = GetDynSole(ent)
                local totalPen = lValidation.penetrationCount + rValidation.penetrationCount
                if totalPen > 2 then ds.correction = ds.correction + 0.04 * dt * 60
                elseif totalPen > 0 then ds.correction = ds.correction + 0.01 * dt * 60
                else ds.correction = ds.correction * (1 - 0.8 * dt) end
                ds.correction = math.Clamp(ds.correction, 0, 1.5)
                dynSoleCorr = ds.correction
                lReqDrop = math.max(lReqDrop - dynSoleCorr, 0); rReqDrop = math.max(rReqDrop - dynSoleCorr, 0)
            end

            local stairsState = state.stairs or {}
            local prevL = stairsState.prevLeftReq or lReqDrop; local prevR = stairsState.prevRightReq or rReqDrop
            local leftRise = math.max(lReqDrop - prevL, 0); local rightRise = math.max(rReqDrop - prevR, 0)
            local leftDrop = math.max(prevL - lReqDrop, 0); local rightDrop = math.max(prevR - rReqDrop, 0)
            local maxRise = math.max(leftRise, rightRise); local maxDrop = math.max(leftDrop, rightDrop)
            local stairAsym = math.abs(lReqDrop - rReqDrop)
            local clampedMin = math.max(stepMinH * modelScale, 2); local clampedMax = math.max(stepMaxH * modelScale, clampedMin + 2)
            local stairRange = math.max(maxRise, maxDrop)
            local stairInRange = (stairRange >= clampedMin and stairRange <= clampedMax) or (stairAsym >= clampedMin * 0.8 and stairAsym <= clampedMax * 1.9)
            local moveEligible = vel2D >= math.max(idleVelThresh * 0.7, 2) and math.abs(velZ) <= 140
            local stairStrong = terrainHint.edgeConfidence >= 0.2 or stairAsym >= clampedMin
            local stairEligible = moveEligible and stairInRange and terrainHint.stable and stairStrong
            UpdateStairSequence(state, {
                leftRise = leftRise, rightRise = rightRise, leftDrop = leftDrop, rightDrop = rightDrop,
                heightDiff = stairAsym, stepMax = clampedMax, edgeConfidence = terrainHint.edgeConfidence,
                surfaceStable = terrainHint.stable, sequenceWindow = stepWindow, eligible = stairEligible,
            })
            state.stairs.prevLeftReq = lReqDrop; state.stairs.prevRightReq = rReqDrop

            local avgDrop = (lReqDrop + rReqDrop) * 0.5; local maxDropSide = math.max(lReqDrop, rReqDrop)
            local hDiff = math.abs(lReqDrop - rReqDrop)
            local dropBias = math.Clamp(0.75 + (hDiff / math.max(scaledLegLen * 0.2, 6)) * 0.25, 0.75, 1.0)
            local reqDrop = Lerp(dropBias, avgDrop, maxDropSide)
            local kneeRange = math.max(scaledLegLen * 0.50, 10)
            local maxKneeExtDist = math.sin(math.rad(math.abs(MIN_KNEE_BEND))) * kneeRange
            local minReqDrop = math.max(maxDropSide - maxKneeExtDist * 0.85, 0)
            reqDrop = math.max(reqDrop, minReqDrop)
            local unevenFactor = math.Clamp(hDiff / 10, 0, 1)
            local terrainNeed = math.Clamp(maxDropSide / math.max(extraDrop * 0.5, 0.3), 0, 1)
            local desiredDrop = reqDrop + Lerp(unevenFactor, extraDrop, extraDropUneven) * terrainNeed + hDiff * GetIKParam("uneven_drop_scale") * 0.2
            local sMode = state.stairs and state.stairs.mode
            local sStair = state.stairs
            if sMode and sStair then
                local stepBias = math.Clamp(sStair.eventHeight / math.max(clampedMax, 1), 0, 1)
                desiredDrop = desiredDrop + sStair.eventHeight * 0.1 * stepBias - sStair.downHeight * 0.06
            end
            local dropCap = math.min(groundDist * 0.95, scaledLegLen * 0.95, maxBodyDropCVar)
            desiredDrop = math.Clamp(desiredDrop, 0, math.max(dropCap, 2))
            if state.bodyDrop then
                local maxStep = math.max(10 * dt * 60, 1.5)
                if sMode and sStair then
                    local ab = sStair.eventHeight * math.Clamp(stairStepMul, 0.25, 2)
                    maxStep = maxStep + math.Clamp(ab * 0.55, 0, 24)
                    if sStair.downHeight > sStair.upHeight then maxStep = maxStep * 0.82 end
                end
                if crouch.inTransition then
                    maxStep = maxStep * 0.35
                    desiredDrop = desiredDrop * math.Clamp(crouch.transitionTime / CROUCH_BLEND_TIME, 0, 1)
                end
                desiredDrop = math.Clamp(desiredDrop, state.bodyDrop - maxStep, state.bodyDrop + maxStep)
            end
            state.bodyDrop = desiredDrop; bodyDrop = desiredDrop

            lKnee = math.deg(math.asin(math.Clamp((bodyDrop - lReqDrop) / kneeRange, -1, 1)))
            rKnee = math.deg(math.asin(math.Clamp((bodyDrop - rReqDrop) / kneeRange, -1, 1)))
            if lKnee > 0 then lKnee = lKnee * GetIKParam("high_foot_bend_boost") end
            if rKnee > 0 then rKnee = rKnee * GetIKParam("high_foot_bend_boost") end
            lKnee = math.Clamp(lKnee, MIN_KNEE_BEND, MAX_KNEE_BEND)
            rKnee = math.Clamp(rKnee, MIN_KNEE_BEND, MAX_KNEE_BEND)

            if antiClip then
                local maxBendAng = MAX_KNEE_BEND / math.max(GetIKParam("high_foot_bend_boost"), 1)
                local maxBendDist = math.sin(math.rad(maxBendAng)) * kneeRange
                local lExcess = bodyDrop - lReqDrop - maxBendDist; local rExcess = bodyDrop - rReqDrop - maxBendDist
                if lExcess > 0.5 and lKnee >= MAX_KNEE_BEND - 1 then penCorrL = lExcess end
                if rExcess > 0.5 and rKnee >= MAX_KNEE_BEND - 1 then penCorrR = rExcess end
                local maxCorr = math.max(penCorrL, penCorrR)
                if maxCorr > 0.5 then
                    local corrBoost = sMode and sStair and (1 + (sStair.confidence or 0) * 0.35) or 1
                    bodyDrop = math.max(bodyDrop - maxCorr * 0.6 * corrBoost, 0)
                    state.bodyDrop = bodyDrop
                    lKnee = math.deg(math.asin(math.Clamp((bodyDrop - lReqDrop) / kneeRange, -1, 1)))
                    rKnee = math.deg(math.asin(math.Clamp((bodyDrop - rReqDrop) / kneeRange, -1, 1)))
                    if lKnee > 0 then lKnee = lKnee * GetIKParam("high_foot_bend_boost") end
                    if rKnee > 0 then rKnee = rKnee * GetIKParam("high_foot_bend_boost") end
                    lKnee = math.Clamp(lKnee, MIN_KNEE_BEND, MAX_KNEE_BEND)
                    rKnee = math.Clamp(rKnee, MIN_KNEE_BEND, MAX_KNEE_BEND)
                end
            end

            lFootRot = ComputeFootRotation(lSamples, footRotScale)
            rFootRot = ComputeFootRotation(rSamples, footRotScale)
        else
            if state.stairs then state.stairs.mode = false; state.stairs.confidence = 0 end
            local airBlend = math.Clamp(math.abs(velZ) / 260, 0, 1)
            local moveBlend = math.Clamp(vel2D / 160, 0, 1)
            local airCycle = CurTime() * (AIR_SWING_SPEED + moveBlend * 3)
            local swing = math.sin(airCycle) * AIR_SWING_AMP * moveBlend
            bodyDrop = math.min((state.bodyDrop or 0) * (1 - dt * 4), AIR_BODY_DROP_MAX * modelScale)
            if bodyDrop <= 0.05 then bodyDrop = 0; state.bodyDrop = nil else state.bodyDrop = bodyDrop end
            local airKnee = Lerp(airBlend, AIR_KNEE_MIN, AIR_KNEE_MAX) + moveBlend * 3
            lKnee = math.Clamp(airKnee + swing, AIR_KNEE_MIN, AIR_KNEE_MAX); rKnee = math.Clamp(airKnee - swing, AIR_KNEE_MIN, AIR_KNEE_MAX)
            local footPitch = Lerp(math.Clamp((velZ + 250) / 500, 0, 1), AIR_FOOT_PITCH_DESCEND, AIR_FOOT_PITCH_ASCEND)
            lFootRot = Angle(0, footPitch + swing * 0.4, 0); rFootRot = Angle(0, footPitch - swing * 0.4, 0)
            if dynamicSole then local ds = GetDynSole(ent); ds.correction = ds.correction * 0.95 end
        end

        if bodyDrop ~= bodyDrop then bodyDrop = 0; state.bodyDrop = nil end
        if lKnee ~= lKnee then lKnee = 0 end; if rKnee ~= rKnee then rKnee = 0 end

        local baseAng = Angle(); local leanAng = Angle()
        if GetIKParamBool("lean_enabled") then
            local bodyAng = ent:GetAngles(); bodyAng.p = 0; local right = bodyAng:Right()
            local lateral = vel.x * right.x + vel.y * right.y
            leanAng = Angle(0, 0, -math.Clamp(lateral / 8, -10, 10))
        end

        return {
            basePos = Vector(0, 0, -bodyDrop), baseAng = baseAng, leanAng = leanAng,
            bodyDrop = bodyDrop, lRequiredDrop = lReqDrop, rRequiredDrop = rReqDrop,
            left = { thigh = Angle(0, -lKnee, 0), calf = Angle(0, lKnee, 0), foot = lFootRot },
            right = { thigh = Angle(0, -rKnee, 0), calf = Angle(0, rKnee, 0), foot = rFootRot },
        }
    end

    -- ============================================================
    -- HUD
    -- ============================================================
    hook.Add("HUDPaint", "CityNPC02Debug", function()
        for _, ent in ipairs(ents.FindByClass("city_anim_test02_npc")) do
            local origin = ent:GetPos() + Vector(0, 0, 90)
            local screen = origin:ToScreen()
            if not screen.visible then continue end
            local status = ent:GetNWString("DebugStatus", "?")
            local bias = ent:GetNWFloat("DebugBias", 0)
            local step = ent:GetNWInt("DebugStep", 0)
            local balanced = ent:GetNWBool("DebugBalanced", false)
            local cyc = ent:GetNWFloat("DebugCycle", 0)
            local footStr = ""
            local lLocal = ent:GetNWVector("FootL"); local rLocal = ent:GetNWVector("FootR")
            if isvector(lLocal) and isvector(rLocal) then
                footStr = "L:" .. string.format(" %.1f %.1f %.1f", lLocal.x, lLocal.y, lLocal.z) .. " R:" .. string.format(" %.1f %.1f %.1f", rLocal.x, rLocal.y, rLocal.z)
            end
            surface.SetFont("CityNPCDebug")
            surface.SetTextColor(Color(255, 255, 100, 255))
            surface.SetTextPos(screen.x - 120, screen.y - 50)
            surface.DrawText(status .. "  B:" .. math.Round(bias, 1) .. "  S:" .. step .. "/6  X:" .. math.Round(cyc, 1) .. "  BAL:" .. tostring(balanced))
            surface.SetTextPos(screen.x - 120, screen.y - 34)
            surface.DrawText(footStr)
        end
    end)

    -- ============================================================
    -- ENT:DRAW
    -- ============================================================
    function ENT:Draw()
        if not IsValid(self) then self:DrawModel(); return end

        if not GetIKParamBool("enabled") then self:DrawModel(); return end

        local bones = GetIKBones(self)
        if not bones or not bones.lFoot then self:DrawModel(); return end

        if not CanManipulateBones(self) then
            ResetPlayer(self, bones); self:DrawModel(); return
        end

        -- model change detection
        if GetIKParamBool("auto_model_detect") then
            local curModel = self:GetModel()
            if self._IKLastModel ~= curModel then
                self._IKLastModel = curModel
                InvalidateModelCache(curModel)
                AutoApplyModelSettings(self)
            end
        end

        StripIK(self, bones)
        self:SetupBones()

        local skeleton = BuildSkeleton(self, bones)
        if skeleton then
            local ok, result = pcall(CalculateIK, self, skeleton)
            if ok and result then
                ApplyResult(self, bones, result)
            end
        end

        self:DrawModel()
    end
end
