# Stratagem blacklist (local R36 build)

Open **MODS > Diver's Best Friend > Blacklist**. Turn **Hide SOS Beacon** on and press **Apply** to omit SOS Beacon from every DBF layout. It defaults off.

For other exclusions, set **Extra stratagem ID 1–8** to an ID in the reference below, then Apply. Each slot holds one exclusion; **0 means empty**. Duplicate IDs are harmless. There are eight extra slots plus the SOS toggle. To restore an entry, clear every slot containing its ID; SOS also requires turning its dedicated toggle off. Changes persist through Mod Options Menu's normal applied settings, including restarts and changing loadouts.

IDs identify stratagems, rather than loadout positions or arrow sequences. SOS Beacon is **145**, Resupply **33**, and Reinforce **124**. The numeric slots fit the existing 32-row settings limit without requiring a new menu dependency. The reference is for supported Steam build **25480438**; a future game build may need an updated reference and adapter.

Exclusions remove entries before native-wheel paging, expanded-wedge geometry, copied-card layout and list navigation. The original top-left vanilla HUD remains present in radial layouts. In DBF list mode, excluded native rows are temporarily hidden; native positions are retained, so gaps can remain. Vanilla manual input and native availability are unchanged. Closing the menu, disabling DBF or switching modes restores stock-row scale with owner and later-change guards.

Applying a blacklist edit cancels queued/armed DBF input. Close and reopen the stratagem menu before using Select on Release again; an edit cannot rearm a different entry during the same held-menu session. If all entries are excluded, DBF clears selection and releases camera capture; Confirm and Select on Release cannot start a sequence. The local build has isolated regression coverage but still needs an in-game smoke test for all layouts, visibility/restoration, persistence, loadout changes and empty lists.

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
