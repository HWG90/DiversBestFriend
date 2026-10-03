# Mission stratagem blacklist (R40)

Open the native stratagem menu once in a mission, then **MODS > Diver's Best Friend > Blacklist**. Three named dropdowns list mission-provided entries and **None**. SOS Beacon and SEAF Artillery appear when present in the local mission payload. There is no separate SOS toggle. Player-equipped stratagem kinds are excluded from the supported-build mission catalog and cannot be blacklisted, including through old saved settings.

Apply changes to save stable native IDs to `DiversBestFriendBlacklist.log` in the loader log directory. None clears a slot. Duplicates are harmless. Initial migration retains up to three distinct mission-only exclusions from the older eight slots and SOS toggle, where present in the first mission. Old equipment exclusions are discarded; additional entries beyond three are not kept as hidden filters. The original Bingus values file is left intact.

Bingus API 1 cannot replace registered choice lists. Choices therefore come from the first successfully read mission payload this game session; restart the game to refresh for another mission. Filtering always checks the current mission payload, so absent entries and unreadable ownership are never excluded. The verified payload reader supplies IDs; names come from the repository's retained supported-build catalog, with SEAF Gun displayed as SEAF Artillery. Unknown equipment and unknown kinds are protected. Bingus supports up to 16 choices; at most 15 mission entries plus None are shown, in native-ID order.

Exclusions apply before paging, geometry and navigation in all four DBF layouts. List mode compacts the remaining rows and restores guarded native geometry on close/disable/switch. Applying an edit cancels pending Confirm and Select on Release jobs; reopen the stratagem menu to rearm release. Empty lists cannot start automation. Vanilla availability and manual input remain unchanged.

Package and isolated LuaJIT verification do not establish live-game menu rendering or gameplay validation. This promotion still needs a fresh-session game smoke test.

## Stratagem ID reference

Names below come from the retained supported-build catalog; mission-only/internal entries may never occur in your loadout. Unlisted IDs may be absent or unnamed. Only IDs 1–149 supported by the current native adapter are accepted.

| ID | Stratagem |
| --- | --- |
| 1 | VEHICLES. BASTION(tank) |
| 2 | BACKPACK. GUARD DOG (Drone) Stun |
| 3 | EAGLE. 500KG BOMB |
| 4 | ORBITAL. GATLING BARRAGE |
| 5 | MISSIONS. ORBITAL ILLUMINATION FLARE |
| 6 | TEAM WEAPONS. COMMANDO |
| 7 | MISSIONS. EXTRACTION BEACON |
| 8 | SENTRYS. FLAMETHROWER |
| 9 | EMPLACEMENTS. ANTI TANK EMPLACEMENT |
| 10 | VEHICLES. COMBAT WALKER OBSIDIAN |
| 11 | MISSIONS. RAISE FLAG |
| 12 | EMPLACEMENTS. ANTI-TANK MINE DEPLOYER |
| 13 | TEAM WEAPONS. LIGHT MACHINE GUN |
| 14 | TEAM WEAPONS. C4 |
| 15 | TEAM WEAPONS. EXPENDABLE ANTI-TANK (Booster) |
| 16 | TEAM WEAPONS. EXPENDABLE MASSIVE ROCKET LAUNCHER |
| 17 | MISSIONS. BUG THUMPER |
| 18 | EAGLE. AIRSTRIKE |
| 19 | MISSIONS. SEISMIC PROBE |
| 20 | PRESIDENT REWARDS. MEDIC BACKPACK |
| 21 | ORBITAL. WALKING BARRAGE |
| 22 | EMPLACEMENTS. SHIELD GENERATOR RELAY |
| 23 | SENTRIES. LASER CANNON SENTRY |
| 24 | BACKPACK. DISPLACEMENT BACKPACK |
| 25 | TEAM WEAPONS. AUTOMATIC CANNON |
| 26 | VEHICLES. FAST RECON VEHICLE (Resupply Auto Turret) |
| 27 | VEHICLES. COMBAT WALKER |
| 28 | MISSIONS. SEAF GUN |
| 29 | MISSIONS. DARK FLUID BACKPACK |
| 30 | EAGLE. AIR SUPPORT |
| 31 | BACKPACK. HELLBOMB |
| 32 | TEAM WEAPONS. HEAVY MACHINEGUN |
| 33 | Resupply |
| 34 | ORBITAL. STATIC FIELD CONDUTORS |
| 35 | EAGLE. (NOT USED) ADDITIONAL STRAFING RUNS |
| 36 | MISSIONS. OIL RIG EXTRACT |
| 37 | PRESIDENT REWARDS. COMBAT WALKER |
| 38 | EAGLE. AIRSTRIKE SMOKE |
| 39 | TEAM WEAPONS. EXPENDABLE NAPALM LAUNCHER |
| 40 | [TUTORIAL] EXTRACTION |
| 41 | ORBITAL. GAS STRIKE |
| 42 | MISSIONS. HELLBOMB |
| 43 | BACKPACK.  GENERATOR PACK |
| 44 | SENTRYS. MORTAR STATICFIELD |
| 45 | TEAM WEAPONS. PLASMA BLASTER |
| 46 | EMPLACEMENTS. GAS MINE DEPLOYER |
| 47 | TANK. TANK RELOAD HE |
| 48 | MISSIONS. DATA JACK |
| 49 | EAGLE. REARM |
| 50 | VEHICLES. STORM(tank) |
| 51 | TEAM WEAPONS. CHAINSAW GREATSWORD |
| 52 | SENTRYS. MORTAR GAS |
| 53 | SENTRYS. ROCKET |
| 54 | TEAM WEAPONS. AIR BURST ROCKET LAUNCHER |
| 55 | BACKPACK. HOVERPACK BACKPACK |
| 56 | TEAM WEAPONS. RAILGUN |
| 57 | BACKPACK. GUARD DOG FLAMETHROWER (Drone) |
| 58 | ORBITAL. RAILCANNON |
| 59 | EMPLACEMENTS. DEFENSE WALL GRENADE LAUNCHER |
| 61 | TEAM WEAPONS. CHEM GUN |
| 62 | ORBITAL. WALKING BARRAGE SMOKE |
| 63 | TEAM WEAPONS. LASER CANNON |
| 64 | MISSIONS. TCS 03 THUMPER |
| 65 | EAGLE. CLUSTERBOMBS |
| 66 | SENTRYS. GATLING |
| 67 | BACKPACK. DIRECTIONAL ENERGY SHIELD |
| 68 | TEAM WEAPONS. ARC THROWER |
| 69 | PRESIDENT REWARDS. ROCKET SENTRY |
| 70 | MISSIONS. PROSPECTING DRILL |
| 71 | MISSIONS. CARGO CONTAINER |
| 72 | MISSIONS. BUG PLUG |
| 73 | BACKPACK. GUARD DOG (Drone) |
| 74 | ORBITAL. SMOKE STRIKE |
| 75 | TEAM WEAPONS. SPEAR |
| 76 | MISSIONS. Cyborg Carry Data |
| 77 | CONSUMABLES. HEALTH PACK RACK |
| 78 | MISSIONS. SHOULDER MOUNTED CAMERA |
| 79 | MISSIONS. Carry Data |
| 80 | TEAM WEAPONS. GRENADE LAUNCHER |
| 81 | TEAM WEAPONS. SHARK ENERGY WEAPON |
| 82 | PRESIDENT REWARDS. MACHINEGUN |
| 83 | ORBITAL. AIRBURST STRIKE |
| 84 | MISSIONS. JAMMED PINATA |
| 85 | MISSIONS. RAISE FLAG NO CLEAR AREA |
| 86 | MISSIONS. REMOTE EXPLOSIVES |
| 87 | TEAM WEAPONS. HEAVY FLAMETHROWER |
| 88 | VEHICLES. COMBAT WALKER BREACHER |
| 89 | TEAM WEAPONS. MINI MISSILE SILO |
| 90 | PRESIDENT REWARDS. HEALTH PACK RACK |
| 91 | VEHICLES. COMBAT WALKER LUMBERER |
| 92 | TEAM WEAPONS. MACHINEGUN |
| 93 | TUTORIAL REINFORCEMENT BEACON |
| 94 | MISSIONS. POISON DRILL |
| 95 | TANK. TANK RELOAD AT |
| 96 | BACKPACK. BALLISTIC SHIELD BACKPACK |
| 97 | TEAM WEAPONS. WASP |
| 98 | MISSIONS. EMERGENCY EXTRACTION BEACON |
| 99 | TEAM WEAPONS. EXPENDABLE MACHINEGUN |
| 100 | TEAM WEAPONS. SLEDGE HAMMER |
| 101 | BACKPACK. SUPPLY BACKPACK |
| 102 | MISSIONS. MOBILE COMMS RELAY |
| 103 | MISSIONS CLAN STATION. Carpet Bombing Run |
| 104 | EMPLACEMENTS. TESLA TOWER |
| 105 | VEHICLES. FAST RECON VEHICLE (FRV) |
| 106 | ORBITAL. NAPALM BARRAGE |
| 107 | ORBITAL. LASER |
| 108 | MISSIONS. Scrambler |
| 109 | PRESIDENT REWARDS. AMMO CACHE |
| 110 | TEAM WEAPONS. MINIGUN |
| 111 | MISSIONS. IMMEDIATE EXTRACTION BEACON |
| 112 | TEAM WEAPONS. FLAMETHROWER |
| 113 | TEAM WEAPONS. HARPOON GUN |
| 114 | TEAM WEAPONS. MELEE FLAG |
| 115 | BACKPACK. Laser Rifle (Drone) |
| 116 | SEAF Squad |
| 117 | SENTRYS. MORTAR |
| 118 | ORBITAL. PRECISION STRIKE |
| 119 | EMPLACEMENTS. ANTI-PERSONNEL MINE DEPLOYER |
| 120 | BACKPACK. HELLBOMB |
| 121 | SENTRYS. MACHINEGUN |
| 122 | MISSIONS. SPIRE STERILIZER |
| 123 | MISSIONS. CALL IN DESTROYER |
| 124 | Reinforce |
| 125 | ORBITAL. 380MM HE BARRAGE |
| 126 | EAGLE. Gas AIRSTRIKE |
| 127 | TEAM WEAPONS. BELT FED GRENADE LAUNCHER |
| 128 | MISSIONS. Upload Discovery |
| 129 | MISSIONS. DRILLING CHARGE |
| 130 | TEAM WEAPONS. RECOILLESS RIFLE |
| 131 | TEAM WEAPONS. GRENADE LAUNCHER TACTICAL |
| 132 | MISSIONS CLAN STATION. Nuke |
| 133 | EAGLE. NAPALM AIRSTRIKE |
| 134 | BACKPACK. JUMPPACK BACKPACK |
| 135 | VEHICLES. FAST RECON VEHICLE (Ramming Flamethrower) |
| 136 | ORBITAL. 120MM HE STRIKE |
| 137 | SENTRYS. AUTOCANNON |
| 138 | MISSIONS. CARGO CONTAINER |
| 139 | EMPLACEMENTS. INCENDIARY MINE DEPLOYER |
| 140 | EAGLE. 110mm ROCKET PODS |
| 141 | TEAM WEAPONS. SNIPER |
| 142 | BACKPACK. GUARD DOG GAS PROJECTOR (Drone) |
| 143 | PRESIDENT REWARDS. JUMPPACK BACKPACK |
| 144 | EMPLACEMENTS. HEAVY MACHINEGUN EMPLACEMENT |
| 145 | SOS Beacon |
| 146 | EAGLE. (NOT USED) AIR-TO-AIR MISSLES |
| 147 | TEAM WEAPONS. EXPENDABLE ANTI-TANK |
| 148 | MISSIONS. EXTRACTION |
| 149 | TEAM WEAPONS. LASER PULSE CANNON |
