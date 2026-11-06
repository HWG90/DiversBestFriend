# .14-diagnostic installation

Reviewed probe b42ca7d, version snapshot 92dfe12. Built from detached worktree
/tmp/dbf-blur-diagnostic-build to exclude unrelated concurrent working edits.
Probe and HUD runtime tests, DLL SDK/import checks, and package verification
passed on that exact snapshot.

Installed mods/divers-best-friend-R50-hellforge.14-diagnostic.zip in the active
HellForge installation; bundle SHA256:
20c50c0a3760945c1e91eebff5cb35a47b9254478394e2bf6d1306873490d98c.
Rollback: backport-backups/dbf-blur-diagnostic-20261106T032216Z.

Probe is off with no command file. In the active session environment's
Local/DBF/HellForge/blur-probe.txt, commands are phase/world numbers:
1 0 = solid triangle square in main world; 2 0 = blurred triangle square;
3 0 = blur bitmap. World 1..8 selects enumerated non-main worlds. Exact same
256x256 square centered at screen center with a separate solid reference bar.
Delete file or write 0 0 to stop; unchanged commands expire after 60s.
No arbitrary code evaluation. Remove diagnostic facility after comparison.
Actual visual comparison and production blur fix remain pending.
