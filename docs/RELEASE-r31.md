# R31 - Scrambled Codes

- Replace blanket rejection of scrambled codes with the native per-stratagem effect query and the same shifted-definition calculation used by the game matcher.
- Use the resolved sequence for both Confirm and Select on Release, including different code lengths. Preserve the selected stratagem identity.
- Recheck the required code before each directional input. If it changes, stop the sequence; close and reopen the menu before selecting again.
- Restore the temporary release binding on interruption. A later clean selection can proceed without reloading the mod.
- Validate source and resolved definitions, position ownership, and native function signatures. Native availability restrictions still apply; this does not bypass jamming.

Install `DiversBestFriend-R31-ScrambledCodes.zip` through Arsenal with the game closed. Test Confirm and, optionally, Select on Release inside and outside the reported scrambling effect. Check entry and exit during an input sequence as well as recovery afterward. Select on Release remains off by default.

Automated regression tests pass. The native query and remapping are derived from the supported game build; live verification against the reported spire/scrambler encounters remains pending.
