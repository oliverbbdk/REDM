Config = {}

Config.Debug = true

Config.MinSpawnDistance = 70.0
Config.MaxSpawnDistance = 95.0

Config.DismountRange = 24.0
Config.TargetDeadCleanupDelay = 5000
Config.GroupSpreadRadius = 10.0
Config.TaskRefreshMs = 1500

Config.Commands = {
    sf = {
        label = 'sheriff',
        count = 4,
        mounted = true,
        animal = false,
        attackStyle = 'ride_dismount_gun',
        pedModels = {
            `S_M_M_DISPATCHLAW_01`,
            `S_M_M_AMBIENTLAWRURAL_01`,
            `U_M_M_NBXSHERIFF_01`,
        },
        horseModels = {
            `A_C_Horse_AmericanPaint_Overo`,
            `A_C_Horse_AmericanStandardbred_Black`,
            `A_C_Horse_HungarianHalfbred_FlaxenChestnut`,
            `A_C_Horse_KentuckySaddle_Black`,
        },
        weapons = {
            `WEAPON_REPEATER_CARBINE`,
            `WEAPON_REVOLVER_CATTLEMAN`,
        }
    },

    nf = {
        label = 'nightfolk',
        count = 7,
        mounted = false,
        animal = false,
        attackStyle = 'rush_melee',
        pedModels = {
            `G_M_M_UniNightfolk_01`,
            `G_M_M_UniNightfolk_02`,
        },
        horseModels = {},
        weapons = {
            `WEAPON_MELEE_KNIFE`,
            `WEAPON_MELEE_HATCHET`,
            `WEAPON_THROWN_BOLAS`,
        }
    },

    is = {
        label = 'indigenous_strike',
        count = 16,
        mounted = true,
        animal = false,
        attackStyle = 'ride_close_attack',
        pedModels = {
            `A_M_M_RhdNative_01`,
            `A_M_M_WapWarriors_01`,
        },
        horseModels = {
            `A_C_Horse_Morgan_Bay`,
            `A_C_Horse_AmericanStandardbred_Black`,
            `A_C_Horse_KentuckySaddle_Black`,
        },
        weapons = {
            `WEAPON_BOW`,
            `WEAPON_TOMAHAWK`,
            `WEAPON_MELEE_KNIFE`,
        }
    },

    wildlife = {
        label = 'wildlife',
        count = 1,
        mounted = false,
        animal = true,
        attackStyle = 'animal_hunt',
        pedModels = {
            `A_C_Bear_01`,
        },
        horseModels = {},
        weapons = {}
    }
}
