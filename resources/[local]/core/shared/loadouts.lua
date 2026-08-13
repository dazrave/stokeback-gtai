-- What you spawn with, by name. One table, shared by every mode - so "a cop's
-- kit" is defined once, not implied by whichever GiveWeaponToPed calls happen
-- to be scattered through a mode's spawn code.
--
-- Shared (not client-only) so the server can name a loadout in an event and
-- the client can apply it without either side hardcoding the contents.
Loadouts = {
    -- The law. Tyres, not heads.
    cop = {
        armour  = 50,
        weapons = {
            { 'WEAPON_PISTOL',      250 },
            { 'WEAPON_NIGHTSTICK',  0   },
            { 'WEAPON_FLASHLIGHT',  0   },
        },
    },

    -- The law, foot-chase spec: the cop kit plus the ender nick-of-time's
    -- scope is explicit about - stop the car with the pistol, stop the man
    -- with the taser. Fifty cartridges is forever in a ten minute round.
    taser = {
        armour  = 50,
        weapons = {
            { 'WEAPON_PISTOL',      250 },
            { 'WEAPON_STUNGUN',     50  },
            { 'WEAPON_NIGHTSTICK',  0   },
            { 'WEAPON_FLASHLIGHT',  0   },
        },
    },

    -- The rabbit. Wheels and nerve, nothing else.
    unarmed = {
        armour  = 0,
        weapons = {},
    },

    -- Free roam and the zombie modes: enough to be dangerous, not enough to
    -- feel safe.
    survivor = {
        armour  = 0,
        weapons = {
            { 'WEAPON_PISTOL', 60 },
            { 'WEAPON_BAT',    0  },
        },
    },
}

-- Client-side applier. Guarded so this file is safe as a shared_script: the
-- server gets the table, only the client gets the function that uses natives.
if not IsDuplicityVersion() then
    function ApplyLoadout(name)
        local kit = Loadouts[name]
        if not kit then return false end

        local ped = PlayerPedId()

        RemoveAllPedWeapons(ped, true)
        SetPedArmour(ped, kit.armour or 0)

        for _, entry in ipairs(kit.weapons or {}) do
            local hash = GetHashKey(entry[1])
            GiveWeaponToPed(ped, hash, entry[2] or 0, false, false)
        end

        -- Holstered, not brandished: spawning mid-conversation with a pistol
        -- already drawn reads as a threat, not a loadout.
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        return true
    end
end
