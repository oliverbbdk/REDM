Config = {}

Config.DebugPrefix = '[HUNTER]'
Config.CleanupDelayMs = 9000
Config.ControllerSelectRadius = 550.0
Config.SpawnDistanceMin = 130.0
Config.SpawnDistanceMax = 190.0
Config.SpawnTryCount = 20
Config.EncounterTimeoutMs = 8 * 60 * 1000

Config.Commands = {
    sf = 'sheriff',
    nf = 'nightfolk',
    is = 'indigenous',
    wildlife = 'wildlife'
}

Config.Groups = {
    sheriff = {
        count = 6,
        mounted = true,
        dismountDistance = 35.0,
        regroupRadius = 20.0,
        pedModels = {
            'S_M_M_Sheriff_01',
            'S_M_M_Sheriff_02',
            'S_M_M_MarshalSRH_01'
        },
        horseModels = {
            'A_C_Horse_AmericanStandardbred_Black',
            'A_C_Horse_Morgan_Bay',
            'A_C_Horse_TennesseeWalker_BlackRabicano'
        },
        weapons = {
            `WEAPON_REPEATER_CARBINE`,
            `WEAPON_REVOLVER_CATTLEMAN`
        }
    },
    nightfolk = {
        count = 7,
        mounted = false,
        regroupRadius = 12.0,
        pedModels = {
            'G_M_M_UniNightfolk_01',
            'G_M_M_UniNightfolk_02',
            'G_M_M_UniNightfolk_03'
        },
        weapons = {
            `WEAPON_MELEE_KNIFE`,
            `WEAPON_MELEE_HATCHET`,
            `WEAPON_THROWN_BOLAS`
        }
    },
    indigenous = {
        count = 16,
        mounted = true,
        dismountDistance = 26.0,
        regroupRadius = 28.0,
        pedModels = {
            'G_M_M_UniInbred_01',
            'A_M_M_NbxDockWorkers_01',
            'A_M_M_RkrRancher_01'
        },
        horseModels = {
            'A_C_Horse_Mustang_GrulloDun',
            'A_C_Horse_AmericanPaint_Overo',
            'A_C_Horse_AmericanPaint_SplashedWhite'
        },
        weapons = {
            `WEAPON_REPEATER_WINCHESTER`,
            `WEAPON_BOW`,
            `WEAPON_SHOTGUN_DOUBLEBARREL`
        }
    },
    wildlife = {
        count = 1,
        mounted = false,
        regroupRadius = 0.0,
        pedModels = {
            'A_C_Bear_01'
        },
        weapons = {}
    }
}
