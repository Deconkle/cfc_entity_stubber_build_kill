AddCSLuaFile()

cfcEntityStubber.registerStub( function()
    local weapon = cfcEntityStubber.getWeapon( "cw_trg42" )
    weapon.AimSpread = 0.0001
end )