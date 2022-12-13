AddCSLuaFile()

local IMPACT_DAMAGE_ENABLED = true
local IMPACT_DAMAGE_MULT = 10 / 7000
local IMPACT_DAMAGE_MIN = 10
local IMPACT_DAMAGE_MAX = 50
local IMPACT_ACCELERATION_THRESHOLD = 7000
local IMPACT_START_DELAY = 0.05
local IMPACT_LIFETIME = 7
local BONK_GUN_CLASS = "m9k_ithacam37"

local IsValid = IsValid


local function mathSign( x )
    if x > 0 then return 1 end
    if x < 0 then return -1 end
    return 0
end

local function enoughToKill( ply, dmgAmount )
    local health = ply:Health()
    local armor = ply:Armor()

    -- Note: this currently doesn't check for godmode
    if dmgAmount >= health + armor then
        return true
    end

    return false
end

local function bonkPlayer( attacker, victim, wep, baseForce )
    local force = baseForce * wep.Bonk.PlayerForceMult
    local zSign = mathSign( force.z )
    local zMin = wep.Bonk.PlayerForceMinZ
    local zMax = wep.Bonk.PlayerForceMaxZ

    -- z-axis ends up being the dominant aspect of what sends a player far or not when they're on the ground
    force.z = math.Clamp( math.abs( force.z ), zMin, zMax ) * zSign
    victim:SetVelocity( force )

    if not IMPACT_DAMAGE_ENABLED then return end

    timer.Simple( IMPACT_START_DELAY, function()
        if not IsValid( victim ) then return end

        local bonkInfo = victim.cfc9k_bonkInfo

        if not bonkInfo then
            bonkInfo = {}
            victim.cfc9k_bonkInfo = bonkInfo
        end

        bonkInfo.Attacker = attacker
        bonkInfo.PrevVel = victim:GetVelocity()
        bonkInfo.IsBonked = true
        bonkInfo.ExpireTime = RealTime() + IMPACT_LIFETIME
    end )
end

local function bonkVictim( attacker, victim, dmg, wep )
    if IsValid( victim ) and victim:IsPlayer() then
        local force = dmg:GetDamageForce()

        -- When both players are on the ground, the force is often downwards, which makes it very weak
        if attacker:IsOnGround() and victim:IsOnGround() then
            force.z = math.abs( force.z )
        end

        -- ETD DamageForce on players only affects their death ragdoll
        if enoughToKill( victim, dmg:GetDamage() ) then
            dmg:SetDamageForce( force * wep.Bonk.PlayerForceMultRagdoll )
        else
            bonkPlayer( attacker, victim, wep, force )
        end
    else
        dmg:SetDamageForce( dmg:GetDamageForce() * wep.Bonk.PropForceMult )
    end
end

local function handleImpact( ply, accel )
    local bonkInfo = ply.cfc9k_bonkInfo

    bonkInfo.IsBonked = false
    bonkInfo.PrevVel = nil
    bonkInfo.Attacker = nil

    local damage = math.Clamp( accel * IMPACT_DAMAGE_MULT, IMPACT_DAMAGE_MIN, IMPACT_DAMAGE_MAX )
    local attacker = IsValid( bonkInfo.Attacker ) and bonkInfo.Attacker or game.GetWorld()
    local wep = ply:GetWeapon( BONK_GUN_CLASS )

    if not IsValid( wep ) then
        wep = attacker
    end

    ply:TakeDamage( damage, attacker, wep )
end

local function detectImpact( ply, dt )
    local bonkInfo = ply.cfc9k_bonkInfo
    if not bonkInfo or not bonkInfo.IsBonked then return end

    local prevVel = bonkInfo.PrevVel

    if not prevVel then
        bonkInfo.PrevVel = ply:GetVelocity()

        return
    end

    if RealTime() > bonkInfo.ExpireTime then
        bonkInfo.IsBonked = false
        bonkInfo.PrevVel = nil
        bonkInfo.Attacker = nil

        return
    end

    local curVel = ply:GetVelocity()
    local velDiff = curVel - prevVel
    local accel = velDiff:Length() / dt
    bonkInfo.PrevVel = curVel

    if accel < IMPACT_ACCELERATION_THRESHOLD then return end

    -- DEBUG
    bonkInfo.Attacker:ChatPrint( "Impact! " .. math.Round( accel ) .. " " .. math.Round( curVel:Length() ) )

    handleImpact( ply, accel )
end


cfcEntityStubber.registerStub( function()
    local weapon = cfcEntityStubber.getWeapon( BONK_GUN_CLASS )

    weapon.Purpose = ""
    weapon.CFC_Category = "Shotgun:Bonk"

    weapon.Primary.RPM = 80
    weapon.Primary.ClipSize = 2
    weapon.Primary.KickUp = 6
    weapon.Primary.KickDown = 4
    weapon.Primary.KickHorizontal = 5
    weapon.Primary.NumShots = 10
    weapon.Primary.Damage = 2
    weapon.Primary.Spread = 0.1
    weapon.Primary.IronAccuracy = 0.08
    weapon.ShellTime = 0.4

    weapon.Bonk = weapon.Bonk or {}
    weapon.Bonk.PlayerForceMult = 0.7
        weapon.Bonk.PlayerForceMinZ = 210
        weapon.Bonk.PlayerForceMaxZ = 400
    weapon.Bonk.PlayerForceMultRagdoll = 300
    weapon.Bonk.PropForceMult = 15
    weapon.Bonk.SelfForce = 600


    weapon._ShootBullet = weapon.ShootBullet or cfcEntityStubber.getWeapon( "bobs_gun_base" ).ShootBullet
    weapon.ShootBullet = function( self, damage, recoil, numBullets, spread )
        local ply = self:GetOwner()
        if not IsValid( ply ) or not ply:IsPlayer() then return end

        -- Self-knockback
        if not ply:IsOnGround() then
            local dir = -ply:GetAimVector()
            ply:SetVelocity( dir * self.Bonk.SelfForce ) -- SetVelocity() when used on a player is additive
        end

        return self:_ShootBullet( damage, recoil, numBullets, spread )
    end

    hook.Add( "EntityTakeDamage", "M9K_Stubber_BonkGun_YeetVictim", function( ent, dmg )
        local attacker = dmg:GetAttacker()
        if not IsValid( attacker ) then return end
        if not attacker:IsPlayer() then return end

        local wep = attacker:GetActiveWeapon()
        if not IsValid( wep ) then return end

        if wep:GetClass() ~= BONK_GUN_CLASS then return end

        bonkVictim( attacker, ent, dmg, wep )
    end )


    if not IMPACT_DAMAGE_ENABLED then return end

    hook.Add( "Think", "M9K_Stubber_BonkGun_DetectImpact", function()
        local dt = FrameTime()
        local plys = player.GetAll()

        for i = 1, #plys do
            local ply = plys[i]

            detectImpact( ply, dt )
        end
    end )
end )






