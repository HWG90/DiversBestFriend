#include "migration.h"
#include "test.h"
#include <string.h>

#define OPT "native_stratagem_radial."

int main(void)
{
    DbfSettings s;
    settings_defaults(&s);
    char options[] =
        "other_mod.cooldown_display\t2\r\n"
        OPT "selection_mode\t1\r\n"
        OPT "select_on_release\ttrue\n"
        OPT "cooldown_display\t3\n"
        OPT "vertical_offset\t-75\n"
        OPT "track_unavailable\ttrue\n"
        OPT "instant_stratagems\tfalse\n"
        OPT "input_interval_ms\t1000\n"
        OPT "blacklist_kind_8\t42\n"
        OPT "hide_eagle_rearm\ttrue";
    CHECK(migration_parse(&s, options, NULL), "recognised options without blacklist file");
    CHECK(s.selection_mode_ordered==3 && s.release_selection_mode==2, "legacy selection and release conversion");
    CHECK(s.cooldown_display==3 && s.track_unavailable && s.vertical_offset==-75, "HUD choice, bool and slider");
    CHECK(s.input_interval_ms==70, "ignore out-of-range interval");
    CHECK(s.blacklist_kind[42] && s.hide_eagle_rearm, "legacy slots and simple hide switches");
    char current[] =
        OPT "selection_mode_ordered\t2\n" OPT "release_selection_mode\t3\n"
        OPT "selection_mode\t3\n" OPT "select_on_release\ttrue\n"
        OPT "hide_sos\ttrue\n" OPT "blacklist_kind_1\t42";
    char v3[] = "29\ttrue\r\n51\ttrue\n149\ttrue\n109\ttrue\n152\ttrue\n"
                "28\ttrue\n50\ttrue\n66\ttrue\n145\ttrue\n154\ttrue\nversion\t3\n";
    settings_defaults(&s);
    CHECK(migration_parse(&s, current, v3), "version can occur after records");
    CHECK(s.selection_mode_ordered==2 && s.release_selection_mode==3, "new choices take precedence");
    CHECK(s.blacklist_kind[28] && s.blacklist_kind[148] && !s.blacklist_kind[42],
          "v3 kinds invert to target, versioned file wins over legacy slots");
    CHECK(s.hide_sos && s.hide_eagle_rearm && !s.blacklist_kind[49] && !s.blacklist_kind[145],
          "single effective SOS/Rearm representation");
    CHECK(!s.blacklist_kind[50] && !s.blacklist_kind[66] && !s.blacklist_kind[109],
          "new and unsupported kinds ignored");
    char expanded[] = OPT "selection_mode_ordered\t2\n" OPT "experimental_layout\t1\n"
                      OPT "selection_mode\t4\n" OPT "hide_sos\ttrue";
    char v2[] = "version\t2\n28\ttrue\n48\ttrue\n49\ttrue\n145\tfalse\n";
    settings_defaults(&s);
    migration_parse(&s, expanded, v2);
    CHECK(s.selection_mode_ordered==1 && s.experimental_layout==2, "legacy expanded override after registration");
    CHECK(s.blacklist_kind[28] && s.blacklist_kind[48] && s.hide_eagle_rearm && !s.hide_sos,
          "v2 uses target IDs and versioned blacklist overrides simple options");
    char v1[] = "version\t1\n1\t145\n2\t42\n3\t49\n4\t7\n";
    settings_defaults(&s);
    migration_parse(&s, NULL, v1);
    CHECK(s.hide_sos && s.hide_eagle_rearm && s.blacklist_kind[42] && !s.blacklist_kind[7], "v1 three target slots");
    char invalid[] = OPT "selection_mode_ordered\t2\n" OPT "selection_mode_ordered\t99\n"
                     OPT "enabled\t0\n" OPT "wheel_size\t100x\n" OPT "cooldown_display\t999999999999999999999\n";
    settings_defaults(&s);
    CHECK(!migration_parse(&s, invalid, NULL) && s.enabled && s.selection_mode_ordered==1,
          "invalid last value and unrelated data do not create an import");
    char empty[] = "version\t3\n";
    CHECK(migration_parse(&s, NULL, empty), "explicit empty blacklist imports");
    CHECK(!migration_parse(&s, NULL, NULL), "no legacy inputs leaves first start alone");
    TEST_MAIN_END
}
