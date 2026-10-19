# Custom Stratagem Compendium compatibility

R45 includes the HUD Plus 0.2.8 compatibility adapter and adds
support for Custom Stratagem Compendium 0.4.1 with HD2Runtime 0.40.0.

Compendium uses ordinary vanilla carrier IDs during missions. HD2Runtime keeps
the carrier's native definition in place but redirects its call-in sequence to
a Runtime-owned immutable array. ASS previously rejected that array because its
address is outside the vanilla settings block. Raising the ID limit would not
fix this problem.

The native definition, local player, mission membership, HUD and input checks
remain. Only an external sequence pointer takes the new path: ASS queries the
already-loaded `hd2runtime/runtime/calldown_codes` module, verifies the supported
ownership method's stripped LuaJIT fingerprint and layout limits, and asks it to
recognise the exact pointer/count pair. Every direction must also match live
memory, be in 1..4, and fit Runtime's nine-direction bound. No module is loaded
or started by ASS, no registry is scanned, and no code data is cached across
input steps. Ownership is checked again before each direction. Unsupported
Runtime implementations refuse custom input rather than accepting unknown memory.

The method fingerprint is `6b49047c` for the shipped 0.40.0 `owned` method.
Its module/function identity is cached; normal vanilla input never queries it.
There is no new per-frame polling, registration enumeration or native patch.
Confirm and Select on Release share the same verified code reader, including
native scrambled-code remapping and cancellation if a sequence changes.

## Offline validation

Actual releases inspected:

- CSC 0.4.1 ZIP SHA-256:
  `d897fe63e1b8a7bc949c5dbb1281ed4e5f3fb571282208efe0bacfef47c30865`
- HD2Runtime 0.40.0 ZIP SHA-256 (matches its published SHA256SUMS.txt):
  `3357d8b2b832dad23dd96af90e21d4fcdea60367a097a172d7e749ddbc1ff0ab`

Use `scripts/verify_custom_stratagems.py --compendium-zip <original.zip>
--runtime-zip <original.zip> --output <review-directory>`. The verifier accepts
only those pinned releases, extracts the actual ownership module and all eleven
custom code lists into review fixtures, then runs the full ASS suite. Set
`HD2_HUD_PLUS_SOURCE` to the extracted HUD Plus 0.2.8 product Lua to run its real
owner/update-wrapper fixture in the same pass. Third-party source and artwork
are not included in ASS's package.

Checks cover all eleven codes through Confirm and Select on Release, native
scramble remapping, absent/unknown owners, interior pointers, count mismatch,
corrupted contents, owner retirement, changed sequences, and the existing R42
ownership, recovery, blacklist and pulse-restoration tests.

Initial code-array validation used shipped Lua and a simulated native address space.
Subsequent LLL gameplay was reported working after restart. Individual coverage
of every family, multiplayer and matched input/performance comparisons remains
unverified.
Neither Compendium nor HD2Runtime was installed or deployed by this work.

Source: https://ayakamods.com/mods/custom-stratagem-compendium.4753/
Runtime source/release: https://github.com/SkyeShade/HD2Runtime/releases/tag/v0.40.0
REA archive Evidence: ev_f14276956e57dbcd65e2b99ff96a0f9cace84194db81c4681953ff213a1c2dee
REA inventory establishes archive identity/contents, not execution.

## October 19 follow-up: Foliage Pass-Through 1.0

The installed Vanilla Plus v42 Foliage Pass-Through option owns 99 projectile
raycast-template edits: ProjectileInfo +0xF4, template 0 -> 2. This caused Runtime
0.40.0's exact donor checks to refuse Gas Barrage (shell 197) and the cluster
launcher (projectile 312). Their native carrier names/codes return after refusal.

The R45 compatibility layer registers exact template-2 variants in Runtime's
Lua review snapshots. Registration requires the known game build, Runtime
0.40.0, Foliage 1.0's applied/owned row, matching native index pointer and buffer
offset, and every byte of the 272-byte live row equal to the original snapshot
except that single 0 -> 2 field. No native memory is written. No comparison or
consumer pin is skipped, and unrecognised edits remain refused. Recognised
variants remain exact snapshots, so later native mutations also fail closed.

Registration traverses only three known schema roots once; startup waits use
bounded owner readiness checks (3,600 updates), with no memory scans while
waiting and no work after completion. It does not retry already-refused mission
slots; load the candidate at startup and begin a fresh mission.

Live read-only verification used isolated copies of the actual loaded schemas
and original shipped Runtime guard functions. Baseline gas/cluster checks failed;
14 exact variants registered in 1-2 ms CPU; both original guards then passed.
An unrelated byte mutation still failed both guards. The original live schemas,
native memory and active mod were unchanged by this test. This establishes guard
compatibility, not observed delivery of every custom family. All eleven code
fixtures and the full ASS regression suite also pass, including Shredder's fix.

R45 release: the LLL predecessor was reported working after restart, including the Shredder exhaustion correction. All compatibility targets remain optional. MDL gameplay is not yet verified.
