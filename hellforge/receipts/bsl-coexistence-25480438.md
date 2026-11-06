# Bingus Shared Loader coexistence on build 25480438

DBF boots its own HUD from its DLL. Players may install a Bingus Shared Loader compatible with their game. DBF has no BSL version requirement. The versions and hashes below identify the two test inputs.

| Tested package | ZIP SHA-256 |
| --- | --- |
| [CowboyBingus v18 release](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v18) | `53af5698aeacfb27b98dfa00054923d11dc854e1e67b4af14798877812a93ba6` |
| [CowboyBingus HellForge package, file 228, v20](https://hf-mod.com/Mods/Details/109?tab=files) | `27ce7311e3688ab525c8b7a325593f117a91a313e663ea68d3e8ea852aac5ec7` |

Both passed against the R50-hellforge.10 exported DLL with SHA-256 `ed40b97456013d956f73a29e1469aede3112bce2366ec24727536b799f0cf0e5`. For each case the HellForge CLI imported BSL into a temporary install and staged it before and after adding DBF. Both stages produced identical game data. The test used the Wwise callback from the staged patch and the DBF DLL from the launch plan. The target game's LuaJIT under Proton ran two VM lifetimes per artifact. Each had one DBF owner and three frames through the BSL-loaded fixture addon's update wrapper, with the stock Wwise functions preserved.

The test substitutes the host SDK hook chain, engine resource lookups and a small registered BSL addon. Filesystem addon discovery, other gameplay mods, machine-code detour installation and visual/in-mission behavior need separate validation. For the v20 build check the upstream fixture supplies the host executable identity in the Wine test process.

To repeat, point `DBF_BSL_ZIP` at the supplied BSL release, `DBF_RELEASE_ZIP` at the inner DBF release, and `DBF_HF_INSTALL` at the build-25480438 HellForge installation. For a loader that checks process identity, set `DBF_BSL_TEST_SOURCE` to a checkout containing its upstream build fixture. From the repository root run:

```sh
python3 -B -m unittest discover -s hellforge/tools -p test_bsl_coexistence.py -v
```

The publisher's HellForge v20 Wwise patch matches its GitHub release and the local October 18 Arsenal installation (SHA-256 `b63cb72f653ceb83e1ac8be47940de6b56fddcf365ea13e73fccd55103dff7e5`). The retained October 19 session log identifies loader-v20 and the target executable/game.dll stamps. A build-25480438 v21 artifact remains unverified. The 0BSD BSL source and the locally supplied game callback have separate provenance. [Upstream third-party inputs](https://github.com/CowboyBingus/BingusSharedLoader/blob/v20/THIRD_PARTY.md)
