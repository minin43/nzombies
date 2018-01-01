AddCSLuaFile( )

ENT.Type = "anim"

ENT.PrintName		= "breakable_entry"
ENT.Author			= "Alig96"
ENT.Contact			= "Don't"
ENT.Purpose			= ""
ENT.Instructions	= ""

ENT.NZOnlyVisibleInCreative = true
ENT.PlankPullOffTime = 1.25

-- models/props_interiors/elevatorshaft_door01a.mdl
-- models/props_debris/wood_board02a.mdl

function ENT:Initialize()

	self:SetModel("models/props_c17/fence01b.mdl")
	self:SetMoveType( MOVETYPE_NONE )
	self:SetSolid( SOLID_VPHYSICS )

	--self:SetHealth(0)
	self:SetCustomCollisionCheck(true)

	if SERVER then
		self.NextPlank = CurTime()
		self.Planks = {}
		self:SetMaxPlanks(6) --GetConVar("nz_difficulty_barricade_planks_max"):GetInt()
		self:ResetPlanks(true)
		self.AttachedZombies = {}
	end
end

function ENT:SetupDataTables()

	self:NetworkVar( "Int", 0, "NumPlanks" )
	self:NetworkVar( "Int", 1, "MaxPlanks" )
	self:NetworkVar( "Bool", 0, "HasPlanks" )
	self:NetworkVar( "Bool", 1, "TriggerJumps" )

end

function ENT:GetPlank(num)
	return self.Planks[num]
end
function ENT:GetNextBrokenPlank()
	local max = self:GetMaxPlanks()
	for i = 1, max do
		if not IsValid(self.Planks[i]) then return i end
	end
end
function ENT:GetNextRepairedPlank()
	local max = self:GetMaxPlanks()
	for i = max, 1, -1 do
		if IsValid(self.Planks[i]) and self.Planks[i].Repaired then return self.Planks[i],i end
	end
end

function ENT:AddPlank(nosound)
	if !self:GetHasPlanks() then return end
	
	if self:SpawnPlank(self:GetNextBrokenPlank()) then
		self:SetNumPlanks( (self:GetNumPlanks() or 0) + 1 )
		if !nosound then
			self:EmitSound("nz/effects/board_slam_0"..math.random(0,5)..".wav")
		end
	end
end

function ENT:GrabPlank(zombie, plank)
	if IsValid(plank) and IsValid(zombie) then
		plank.Repaired = false
	end
	return CurTime() + self.PlankPullOffTime
end

function ENT:RemovePlank(plank, dir)

	local plank = plank or self:GetNextRepairedPlank()
	
	if IsValid(plank) then
		-- Drop off
		plank:SetParent(nil)
		plank:PhysicsInit(SOLID_VPHYSICS)
		local entphys = plank:GetPhysicsObject()
		if entphys:IsValid() then
			entphys:EnableGravity(true)
			entphys:Wake()
			if dir then
				entphys:SetVelocity(dir*200)
			end
		end
		plank:SetCollisionGroup( COLLISION_GROUP_DEBRIS )
		-- Remove
		SafeRemoveEntityDelayed(plank, 1)
	end
	
	table.RemoveByValue(self.Planks, plank)
	self:SetNumPlanks( self:GetNumPlanks() - 1 )
end

function ENT:ResetPlanks(nosoundoverride)
	if self:GetHasPlanks() then
		for i=1, self:GetMaxPlanks() do
			self:AddPlank(!nosoundoverride)
		end
	end
end

function ENT:Use( activator, caller )
	if CurTime() > self.NextPlank then
		if self:GetHasPlanks() and self:GetNumPlanks() < self:GetMaxPlanks() then
			self:AddPlank()
                  activator:GivePoints(10)
				  activator:EmitSound("nz/effects/repair_ching.wav")
			self.NextPlank = CurTime() + 1
		end
	end
end

local plankpos = {
	{Vector(-1,0,30),110},
	{Vector(-3,15,15),-12},
	{Vector(-3,-15,15),8},
	{Vector(-5,0,30),85},
	{Vector(-5,0,20),95},
	{Vector(-5,0,0),80},
}
function ENT:SpawnPlank(num)
	-- Spawn
	if IsValid(self.Planks[num]) then return end
	
	local plank = ents.Create("breakable_entry_plank")
	local pos, ang
	if num > #plankpos then
		local angs = {-60,-70,60,70}
		local min = self:GetTriggerJumps() and 0 or -45
		pos = Vector(0,0, math.random( min, 45 ))
		ang = table.Random(angs)
	else
		pos = plankpos[num][1]
		ang = plankpos[num][2]
	end
	
	plank:SetParent(self)
	plank:SetCollisionGroup( COLLISION_GROUP_DEBRIS )
	plank:Repair(self, pos, ang)
	plank:Spawn()
	
	self.Planks[num] = plank
	
	return true
end

local POS_BACK_M = 1
local POS_BACK_L = 2
local POS_BACK_R = 3
local POS_FRONT_M = 4
local POS_FRONT_L = 5
local POS_FRONT_R = 6
local attachpos = {
	Vector(35,0,-45),
	Vector(3,-2,-45),
	Vector(3,2,-45),
	Vector(-10,0,-45),
	Vector(-3,-2,-45),
	Vector(-3,2,-45),
}
function ENT:GetEmptyAttachSlot(zombie)
	local side = (zombie:GetPos()-self:GetPos()):Dot(self:GetAngles():Forward()) < 0 and 4 or 1
	for i = side,side+2 do
		if not IsValid(self.AttachedZombies[i]) then return i end
	end
end
function ENT:GetAttachPosition(pos)
	local v = attachpos[pos]
	if v then
		local vec = Vector(v.x,v.y,v.z)
		local ang = self:GetAngles()
		vec:Rotate(ang)
		if pos < 4 then
			ang = (ang:Forward()*-1):Angle()
		end
		return vec + self:GetPos(), ang
	end
end
function ENT:AttachZombie(zombie, pos)
	if not IsValid(self.AttachedZombies[pos]) then
		self.AttachedZombies[pos] = zombie
		return true
	end
end

function ENT:Touch(ent)
	--if self:GetTriggerJumps() and self:GetNumPlanks() == 0 then
		--if ent.TriggerBarricadeJump then ent:TriggerBarricadeJump(self, self:GetTouchTrace().HitNormal) end
	--end
end

hook.Add("ShouldCollide", "zCollisionHook", function(ent1, ent2)
	if IsValid(ent1) and ent1:GetClass() == "breakable_entry" and nzConfig.ValidEnemies[ent2:GetClass()] and !ent1:GetTriggerJumps() and ent1:GetNumPlanks() == 0 then
		if !ent1.CollisionResetTime then
			ent1:SetSolid(SOLID_NONE)
		end
		ent1.CollisionResetTime = CurTime() + 0.1
	end
	
	if IsValid(ent2) and ent2:GetClass() == "breakable_entry" and nzConfig.ValidEnemies[ent1:GetClass()] and !ent2:GetTriggerJumps() and ent2:GetNumPlanks() == 0 then
		if !ent2.CollisionResetTime then
			ent2:SetSolid(SOLID_NONE)
		end
		ent2.CollisionResetTime = CurTime() + 0.1
	end
end)

if CLIENT then
	function ENT:Draw()
		if ConVarExists("nz_creative_preview") and !GetConVar("nz_creative_preview"):GetBool() and nzRound:InState( ROUND_CREATE ) then
			self:DrawModel()
		end
	end
else
	function ENT:Think()
		if self.CollisionResetTime and self.CollisionResetTime < CurTime() then
			self:SetSolid(SOLID_VPHYSICS)
			self.CollisionResetTime = nil
		end
	end
end
