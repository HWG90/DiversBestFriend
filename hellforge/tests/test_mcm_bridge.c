/* Default suite: inject a recording API. tests/mcm/run_native.sh runs the same lifecycle
 * against the native registry and also exercises its schema, controls and save transaction. */
#include "dbf_mcm.h"
#include "hud_options.h"
#include "test.h"
#include <string.h>
#include <stdlib.h>

static DbfSettings live;
static unsigned resolves, registrations, saves, batches;
static bool online, fail_save, reject_registration;
static McmApi api;
static McmMod *mod;
static McmMod *(*register_impl)(const char *, size_t, const McmCallbacks *);
static int (*batch_impl)(McmMod *, const char *, size_t);
static McmCallbacks callbacks;

static bool persist(const DbfSettings *candidate)
{
    ++saves;
    if (fail_save) return false;
    live = *candidate;
    return true;
}

static const McmApi *resolve(void)
{
    ++resolves;
    return online ? &api : NULL;
}

static void tick(void) { dbf_mcm_tick(&live, persist, resolve); }

static McmMod *record_register(const char *json, size_t len, const McmCallbacks *cb)
{
    ++registrations;
    if (reject_registration) return NULL;
    callbacks = *cb;
    mod = register_impl(json, len, cb);
    return mod;
}

static int record_batch(McmMod *m, const char *json, size_t len)
{
    ++batches;
    return batch_impl(m, json, len);
}

#ifdef DBF_TEST_NATIVE_MCM
#include "api.h"
#include "mem_fs.h"
static FsPort *fs;
static Registry *registry;
static Queue *queue;
static uint64_t game_thread(void) { return 1; }

static void setup(void)
{
    fs = mem_fs_new();
    registry = registry_new(fs, NULL, NULL);
    queue = queue_new(16);
    api_bind(registry, queue, game_thread(), game_thread);
    api = *api_table();
}

static void cleanup(void)
{
    queue_free(queue);
    registry_free(registry);
    mem_fs_free(fs);
}

static void controls(void)
{
    CHECK(api.open() && dbf_mcm_open() && api.close() && !dbf_mcm_open(),
          "bridge follows native MCM window state");
    CHECK(api.find("divers_best_friend")==mod, "native registry finds the bridge by its public id");
    for (unsigned i=0; i<hud_option_count(); ++i) {
        const HudOption *option=hud_option_descriptor(i);
        McmValue v={0};
        int value=hud_option_get(&live,option->key);
        CHECK(api.get(mod,option->key,&v) &&
              (option->widget==HUD_TOGGLE ? v.type==MCM_BOOL && v.boolean==value
                                           : v.type==MCM_NUMBER && v.number==value), option->key);
    }
    CHECK(api.available(mod,"dock_gap"), "dock gap available while cooldown display is enabled");
    McmValue off={.type=MCM_BOOL,.boolean=0};
    unsigned draft_saves=saves;
    CHECK(api.edit(mod,"cooldown_icons",&off) && !api.available(mod,"dock_gap") &&
          live.cooldown_icons && saves==draft_saves,
          "unconfirmed parent disables the dependent control without changing DBF");
    CHECK(api.discard(mod,"cooldown") && api.available(mod,"dock_gap"), "discard restores dependent availability");
    CHECK(api.set(mod,"cooldown_icons",&off) && !live.cooldown_icons &&
          !api.available(mod,"dock_gap"), "MCM toggle persists and disables its dependent control");
    /* DBF's editor changed an unrelated setting after the previous bridge tick.
     * MCM saves its entire map, including its stale value for this disabled control. */
    McmValue pad={.type=MCM_TEXT,.text="pad_dpad_right"};
    CHECK(api.edit(mod,"bind_slot2",&pad) && live.bind[BIND_SLOT2].kind==BIND_NONE,
          "binding stays drafted before the DBF editor update");
    live.dock_gap=40;
    unsigned prior=saves;
    McmValue on={.type=MCM_BOOL,.boolean=1}, gap={0};
    CHECK(api.set(mod,"kind_5",&on) && live.blacklist_kind[5] && live.dock_gap==40 && saves==prior+1,
          "MCM exclusion preserves the newer DBF edit in its full-map save");
    tick();
    CHECK(api.get(mod,"dock_gap",&gap) && gap.type==MCM_NUMBER && gap.number==40 &&
          !api.available(mod,"dock_gap") && saves==prior+1,
          "DBF can mirror a disabled slider without saving again or enabling it");
    unsigned before=saves;
    McmValue draft={0};
    CHECK(api.preview(mod,"bind_slot2",&draft) && draft.type==MCM_TEXT && draft.text &&
          !strcmp(draft.text,"pad_dpad_right") && live.bind[BIND_SLOT2].kind==BIND_NONE,
          "mirroring the disabled slider preserves the unrelated MCM binding draft");
    CHECK(api.confirm(mod,"bindings") && live.bind[BIND_SLOT2].kind==BIND_PAD &&
          live.bind[BIND_SLOT2].code==8 && saves==before+1, "confirmation persists the controller binding once");
    McmValue invalid={.type=MCM_TEXT,.text="pad_invalid"};
    CHECK(!api.set(mod,"bind_slot2",&invalid) && saves==before+1 && live.bind[BIND_SLOT2].code==8,
          "invalid binding preserves the confirmed control");
    CHECK(!mem_fs_get(fs,"divers_best_friend.ini"), "DBF owns settings persistence");
}
#else
/* This fixture models a single saved toggle. Schema validation and storage of
 * the other controls run through the unmodified MCM code in the native build. */
static int fake_handle;
static McmValue sound;
static bool fake_controls_committed;
static char loaded[16384];
static int open_state;
static const char *fake_error(void) { return ""; }
static int fake_is_open(void) { return open_state; }
static int fake_open(void) { open_state=1; return 1; }
static int fake_close(void) { open_state=0; return 1; }
static McmMod *fake_find(const char *id)
{
    return !strcmp(id,"divers_best_friend") ? mod : NULL;
}
static int fake_get(McmMod *m, const char *id, McmValue *out)
{
    if (!mod || m!=mod) return 0;
    if (!strcmp(id,"selection_sounds")) { *out=sound; return 1; }
    if (fake_controls_committed && !strcmp(id,"kind_5")) {
        *out=(McmValue){.type=MCM_BOOL,.boolean=1}; return 1;
    }
    if (fake_controls_committed && !strcmp(id,"bind_slot2")) {
        *out=(McmValue){.type=MCM_TEXT,.text="pad_dpad_right"}; return 1;
    }
    size_t key_len=strlen(id);
    for (const char *row=loaded; *row; row+=strlen(row)+1) {
        if (strncmp(row,id,key_len) || row[key_len]!='=') continue;
        const char *value=row+key_len+1;
        if (value[0]=='@') *out=(McmValue){.type=MCM_TEXT,.text=value+1};
        else if (!strcmp(value,"true") || !strcmp(value,"false"))
            *out=(McmValue){.type=MCM_BOOL,.boolean=value[0]=='t'};
        else *out=(McmValue){.type=MCM_NUMBER,.number=strtol(value,NULL,10)};
        return 1;
    }
    return 0;
}

static McmMod *fake_register(const char *json, size_t length, const McmCallbacks *cb)
{
    int len=cb->load(cb->user,loaded,sizeof loaded-1);
    if (len<=0 || (size_t)len>=sizeof loaded-1) return NULL;
    CHECK(strstr(loaded,"selection_sounds=false"),
          "late registration loads the nondefault DBF value");
    for (int i=0;i<len;++i) if (loaded[i]=='\n') loaded[i]=0;
    sound=(McmValue){.type=MCM_BOOL,.boolean=0};
    return (McmMod *)&fake_handle;
}

static int fake_set(McmMod *m, const char *id, const McmValue *v)
{
    if (!m || strcmp(id,"selection_sounds") || v->type!=MCM_BOOL) return 0;
    const char *ini=v->boolean ? "selection_sounds=true\n" : "selection_sounds=false\n";
    if (!callbacks.save(callbacks.user,ini,strlen(ini))) return 0;
    McmValue previous=sound;
    sound=*v;
    if (callbacks.changed) callbacks.changed(callbacks.user,id,v,&previous);
    return 1;
}

static int fake_batch(McmMod *m, const char *json, size_t len)
{
    /* Deliver the synchronous storage callback that a real set_many invokes. */
    McmValue on={.type=MCM_BOOL,.boolean=1};
    return strstr(json,"\"selection_sounds\":true") && fake_set(m,"selection_sounds",&on);
}

static int fake_refresh(McmMod *m) { return 0; }
static void setup(void)
{
    api=(McmApi){.version=MCM_API_VERSION,.size=sizeof api,.register_mod=fake_register,
        .get=fake_get,.preview=fake_get,.set=fake_set,.set_many=fake_batch,
        .refresh_conditions=fake_refresh,.find=fake_find,.error=fake_error,.open=fake_open,.close=fake_close,.is_open=fake_is_open};
}
static void controls(void)
{
    unsigned before=saves;
    open_state=1;
    CHECK(dbf_mcm_open(),"bridge reports open MCM window");
    open_state=0;
    CHECK(!dbf_mcm_open(),"bridge reports closed MCM window");
    const char edits[]="kind_5=true\nbind_slot2=@pad_dpad_right\n";
    CHECK(callbacks.save(callbacks.user,edits,sizeof edits-1) && live.blacklist_kind[5] &&
          live.bind[BIND_SLOT2].kind==BIND_PAD && live.bind[BIND_SLOT2].code==8 && saves==before+1,
          "provider persists a controller binding and exclusion together");
    fake_controls_committed=true;
}
static void cleanup(void) {}
#endif

int main(void)
{
    setup();
    register_impl=api.register_mod;
    batch_impl=api.set_many;
    api.register_mod=record_register;
    api.set_many=record_batch;
    settings_defaults(&live);
    live.selection_sounds=false;
    tick();
    tick();
    CHECK(resolves>0 && !dbf_mcm_registered() && !dbf_mcm_open() && !registrations && !saves,
          "an absent optional registry leaves DBF settings alone");
    online=true;
    reject_registration=true;
    api.open();
    tick();
    CHECK(!dbf_mcm_registered() && registrations==1 && dbf_mcm_open() && !saves,
          "bridge reports MCM open even when registration is refused");
    api.close();
    reject_registration=false;
    for (unsigned frame=0; frame<302 && !dbf_mcm_registered(); ++frame) tick();
    CHECK(dbf_mcm_registered() && registrations==2 && mod && !saves,
          "later tick retries registration without saving DBF");
    if (!mod) { if (api.error) fprintf(stderr,"MCM: %s\n",api.error()); cleanup(); return 1; }
    McmValue value={0};
    CHECK(api.get(mod,"selection_sounds",&value) && value.type==MCM_BOOL && !value.boolean,
          "registry starts from live DBF settings");
    controls();
    unsigned previous_saves=saves;
    unsigned previous_batches=batches;
    live.selection_sounds=true;
    tick();
    CHECK(api.get(mod,"selection_sounds",&value) && value.type==MCM_BOOL && value.boolean &&
          batches==previous_batches+1 && saves==previous_saves,
          "DBF edit mirrors to MCM once without recursively persisting");
    McmValue off={.type=MCM_BOOL,.boolean=0};
    fail_save=true;
    CHECK(!api.set(mod,"selection_sounds",&off) && live.selection_sounds &&
          api.get(mod,"selection_sounds",&value) && value.boolean && saves==previous_saves+1,
          "failed DBF save rejects the MCM edit and preserves both values");
    fail_save=false;
    CHECK(api.set(mod,"selection_sounds",&off) && !live.selection_sounds &&
          api.get(mod,"selection_sounds",&value) && !value.boolean && saves==previous_saves+2,
          "retry commits the MCM edit to DBF once");
    previous_batches=batches;
    tick();
    tick();
    CHECK(saves==previous_saves+2 && batches==previous_batches && registrations==2,
          "subsequent ticks do not echo, save or re-register the committed edit");
    cleanup();
    TEST_MAIN_END
}
