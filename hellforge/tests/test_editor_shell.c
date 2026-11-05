#include <string.h>
#include "editor_shell.h"
#include "fake_ov.h"
#include "hud_options.h"
#include "ui_settings.h"
#include "settings_editor.h"
#include "test.h"

static OvApi host;
static DbfSnapshot snapshot;
static OvFrame frame = {.width=1920, .height=1080, .scale=1, .capturing=1};
static struct OvPanel { int open; } panel;
static int pressed, control, children, child_calls, layer, layers, focus, closes;
static int colors, disabled, blocked, ids, current_id, click_view = -1;
static bool disable_flags[16];
static int text_input, focused = 1;
static float region_width=1000;
static bool invalid, focus_next;
static char focused_field[128];
static const char *click, *edit, *binding;
static void noop(void) {}
static int is_focused(void) { return focused; }
static int editing(void) { return text_input; }
static int no(void) { return 0; }
static int key_pressed(int key) { return key == pressed; }
static int key_down(int key) { return key == 0x11 && control; }
static void begin_child(const char* id, float width, float height, int border)
{
    if (layer != OV_LAYER_WINDOW) invalid=true;
    ++children;
    ++child_calls;
}
static void end_child(void) { if (--children < 0) invalid = true; }
static void draw_layer(int next)
{
    if (next != (layers == 0 ? OV_LAYER_WINDOW : OV_LAYER_BACKGROUND)) invalid=true;
    layer = next;
    ++layers;
}
static void keyboard_focus(void) { ++focus; focus_next = true; }
static int input_text(const char* label, char* buffer, size_t size)
{
    if (focus_next) snprintf(focused_field, sizeof focused_field, "%s", label);
    focus_next = false;
    if (binding && !strcmp(label, "New binding")) {
        snprintf(buffer, size, "%s", binding);
        return 1;
    }
    return 0;
}
static void set_open(OvPanel* p, int open)
{
    if (p != &panel || open) invalid = true;
    panel.open = open;
    ++closes;
}
static int button(const char* label)
{
    return !blocked && click && !strcmp(label, click);
}
static int checkbox(const char* label, int* value)
{
    if (!edit || strcmp(edit,label)) return 0;
    *value = !*value;
    return 1;
}
static int combo(const char* label, int* value, const char* const* items, int n) { return 0; }
static int slider_int(const char* label, int* value, int min, int max) { return 0; }
static void width(float pixels) {}
static void avail(float* w, float* h) { if (w) *w=region_width; if (h) *h=640; }
static void origin(float* x, float* y) { if (x) *x=20; if (y) *y=30; }
static void cursor(float x, float y) {}
static void rect(float* x0, float* y0, float* x1, float* y1)
{
    origin(x0,y0);
    if (x1) *x1=1020;
    if (y1) *y1=670;
}
static void push_int(int id) { current_id=id; ++ids; }
static void pop_id(void) { if (--ids < 0) invalid=true; }
static void begin_disabled(int flag)
{
    if (disabled >= 16) { invalid=true; return; }
    disable_flags[disabled++] = flag != 0;
    if (flag) ++blocked;
}
static void end_disabled(void)
{
    if (disabled == 0) { invalid=true; return; }
    if (disable_flags[--disabled]) --blocked;
}
static int selectable(const char* label, int selected) { return button(label); }
static int selectable_ex(const char* label, int selected, float w, float h, int span)
{
    if (!strcmp(label,"##view")) return click_view == current_id;
    return selectable(label,selected);
}
static void line(float x0,float y0,float x1,float y1,uint32_t color,float thickness) {}
static void outline(float x0,float y0,float x1,float y1,uint32_t color,float rounding,float thickness) {}
static void triangle(float x0,float y0,float x1,float y1,float x2,float y2,uint32_t color) {}
static void label(const char* text) {}
static void textf(const char* format, ...) {}
static void circle(float x, float y, float radius, uint32_t color, float thickness) {}
static void push_color(int slot,uint32_t color) { ++colors; }
static void pop_color(int n) { colors-=n; if(colors<0) invalid=true; }
static int bold(void) { return 2; }

static void setup(void)
{
    host = *fake_ov_api();
    host.version=OV_API_VERSION;
    host.draw_line=line;
    host.draw_rect=outline;
    host.draw_triangle_filled=triangle;
    host.bold_font=bold;
    host.heading=label;
    host.key_cap=label;
    host.textf=textf;
    host.small_button=button;
    host.draw_circle=circle;
    host.button=button;
    host.button_primary=button;
    host.checkbox=checkbox;
    host.combo=combo;
    host.slider_int=slider_int;
    host.want_text_input=editing;
    host.is_focused=is_focused;
    host.key_down=key_down;
    host.key_pressed=key_pressed;
    host.begin_child=begin_child;
    host.end_child=end_child;
    host.draw_layer=draw_layer;
    host.input_text=input_text;
    host.set_keyboard_focus_here=keyboard_focus;
    host.set_open=set_open;
    host.same_line=noop;
    host.begin_disabled=begin_disabled;
    host.end_disabled=end_disabled;
    host.set_next_item_width=width;
    host.push_id_int=push_int;
    host.pop_id=pop_id;
    host.selectable=selectable;
    host.selectable_ex=selectable_ex;
    host.content_region_avail=avail;
    host.cursor_screen_pos=origin;
    host.set_cursor_screen_pos=cursor;
    host.window_rect=rect;
    host.item_rect=rect;
    host.is_item_hovered=no;
    host.is_item_active=no;
    host.push_color=push_color;
    host.pop_color=pop_color;
}

static const char* const tabs[]={"BROWSE","CHANGES","CONTROLS","BLACKLIST","STATUS"};

static void draw(const DbfSnapshot* data)
{
    fake_ov_reset();
    invalid=focus_next=false;
    focused_field[0]=0;
    children=child_calls=layers=focus=ids=disabled=blocked=colors=0;
    layer=OV_LAYER_BACKGROUND;
    editor_shell_draw(&host,data,&frame,&panel);
    CHECK(!invalid && !colors && !children && !ids && !disabled && !fake_ov_open() &&
          !fake_ov_misuse() && !fake_ov_overflowed(), "balanced host scopes");
    CHECK(layer==OV_LAYER_BACKGROUND,"restored caller draw layer");
    pressed=control=0;
    click_view=-1;
    click=edit=binding=NULL;
}

static void expect_tab(int selected)
{
    CHECK(child_calls>0 && layers>=2,"drew window contents in a child and restored draw layer");
    for (int i=0;i<5;i++) {
        char line[96];
        int token = i==selected ? OV_THEME_ACCENT : OV_THEME_TEXT_DIM;
        snprintf(line,sizeof line,"dtext:%08X:%s",(unsigned)fake_ov_theme_color(token),tabs[i]);
        if (fake_ov_find(line,0)<0) printf("  expected header item %s\n",line);
        CHECK(fake_ov_find(line,0)>=0,tabs[i]);
    }
}

static void keyboard(int vk,bool ctrl)
{
    pressed=vk;
    control=ctrl;
    draw(&snapshot);
}

static void availability(void)
{
    CHECK(editor_shell_available(&host),"modern host offers editor shell");
    CHECK(!editor_shell_available(NULL),"absent host");
    OvApi partial=host;
    partial.version=5;
    CHECK(!editor_shell_available(&partial),"legacy version stays on the original window");
    partial=host;
    partial.size=offsetof(OvApi,bold_font);
    CHECK(!editor_shell_available(&partial),"truncated modern table stays on the original window");
    /* A same-version host can omit one operation. Exercise the admission
     * decision before drawing with that table: the real calls are unconditional. */
#define REQUIRE_CALLBACK(field) do { \
        partial=host; partial.field=NULL; \
        CHECK(!editor_shell_available(&partial), "partial host missing " #field " selects fallback"); \
    } while (0)
    REQUIRE_CALLBACK(end_child);
    REQUIRE_CALLBACK(draw_line);
    REQUIRE_CALLBACK(set_keyboard_focus_here);
    REQUIRE_CALLBACK(is_item_active);
    REQUIRE_CALLBACK(push_color);
    REQUIRE_CALLBACK(pop_color);
    REQUIRE_CALLBACK(text);
    REQUIRE_CALLBACK(text_disabled);
    REQUIRE_CALLBACK(separator);
    REQUIRE_CALLBACK(begin_table);
    REQUIRE_CALLBACK(end_table);
    REQUIRE_CALLBACK(table_setup_column);
    REQUIRE_CALLBACK(table_headers_row);
    REQUIRE_CALLBACK(table_next_row);
    REQUIRE_CALLBACK(table_next_column);
#undef REQUIRE_CALLBACK
    partial=*fake_ov_api();
    CHECK(!editor_shell_available(&partial),"legacy partial fixture selects fallback");
    fake_ov_reset();
    ui_settings_draw(&partial,&snapshot);
    CHECK(fake_ov_find("tabbar:dbf-tabs",0)>=0 && fake_ov_find("tab:Status",0)>=0 &&
          !fake_ov_open() && !fake_ov_misuse(),"legacy fallback draws its status tab");
}

int main(void)
{
    setup();
    snap_init();
    settings_defaults(&snapshot.options);
    snapshot.tick=1;
    snapshot.build_ok=true;
    snapshot.host_version=host.version;
    panel.open=1;
    availability();
    draw(&snapshot);
    expect_tab(0);
    for (int i=1; i<=5; ++i) {
        keyboard(0x75,false);
        expect_tab(i%5);
        if (i==2) {
            CHECK(fake_ov_count_prefix("text:Current binding:")>0,"Controls shows binding editor");
            click="Slot 2";
            draw(&snapshot);
            binding="key:q";
            click="APPLY BINDING";
            draw(&snapshot);
            UiEvent e;
            CHECK(ui_drain(&e,1)==1 && e.kind==UI_BINDING && e.a==BIND_SLOT2 &&
                  editor_apply(&snapshot.options,&e) && snapshot.options.bind[BIND_SLOT2].code=='Q',
                  "Controls posts the selected slot binding");
        }
        if (i==3) {
            edit="SOS Beacon";
            draw(&snapshot);
            UiEvent e;
            CHECK(!ui_drain(&e,1),"Blacklist checkbox stays staged until Apply");
            click="APPLY BLACKLIST";
            draw(&snapshot);
            CHECK(ui_drain(&e,1)==1 && e.kind==UI_BLACKLIST && editor_apply(&snapshot.options,&e) &&
                  snapshot.options.hide_sos, "Blacklist applies the selected mission entry");
        }
        if (i==4) CHECK(fake_ov_find("text:Game build 25480438: OK",0)>=0,"Status shows build diagnostics");
    }
    edit="Enabled";
    draw(&snapshot);
    UiEvent staged;
    CHECK(ui_drain(&staged,1)==0 && snapshot.options.enabled,"a Browse edit stays staged until Apply");
    keyboard('E',true);
    expect_tab(1);
    CHECK(fake_ov_find("text_wrapped:Enable Mod",0)>=0,"Changes lists the staged setting");
    click="DISCARD";
    draw(&snapshot);
    keyboard('F',true);
    expect_tab(0);
    CHECK(focus==1 && strcspn(focused_field,"#")==6 && !strncmp(focused_field,"Search",6),"Ctrl+F focuses a Browse input in the same frame");
    text_input=1;
    keyboard(0x75,false);
    expect_tab(0);
    text_input=0;
    focused=0;
    keyboard('E',true);
    expect_tab(0);
    focused=1;

    region_width=620;
    click_view=2;
    draw(&snapshot);
    draw(&snapshot);
    expect_tab(2);
    region_width=1000;

    keyboard('F',true);
    snapshot.options.cooldown_display=3;
    click="RESET TO DEFAULTS";
    draw(&snapshot);
    UiEvent event[2];
    CHECK(ui_drain(event,2)==0,"reset stages a draft without changing live settings");
    keyboard('E',true);
    keyboard(0x78,false);
    int count=ui_drain(event,2);
    CHECK(count==1 && event[0].kind==UI_HUD_OPTION && event[0].a>=0 &&
          hud_option_key((unsigned)event[0].a) &&
          !strcmp(hud_option_key((unsigned)event[0].a),"cooldown_display") && event[0].b==1,
          "F9 applies staged cooldown style to the game-thread event queue");

    keyboard(0x1b,false);
    CHECK(closes==1 && !panel.open,"Escape closes the supplied panel");
    panel.open=1;
    click="X##close";
    draw(&snapshot);
    CHECK(closes==2 && !panel.open,"X closes the supplied panel");
    TEST_MAIN_END
}
