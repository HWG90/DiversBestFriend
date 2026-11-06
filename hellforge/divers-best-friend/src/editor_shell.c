#include "editor_shell.h"
#include "editor_browse.h"
#include "editor_icons.h"
#include "settings_editor.h"
#include "text.h"
#include "ui_settings.h"

enum View { BROWSE, CONTROLS, BLACKLIST, CHANGES, STATUS, VIEW_COUNT };
static const char* const labels[] = {"SETTINGS", "KEY BINDINGS", "EXCLUSIONS", "REVIEW", "DIAGNOSTICS"};
static enum View view;

bool editor_shell_available(const OvApi* ov)
{
    return ov && ov->version >= 6 && ov->size >= offsetof(OvApi, bold_font) + sizeof ov->bold_font &&
           editor_browse_available(ov) && ov->bold_font && ov->key_cap && ov->button_primary &&
           ov->selectable_ex && ov->cursor_screen_pos && ov->set_cursor_screen_pos && ov->draw_layer &&
           ov->draw_rect_filled && ov->draw_line && ov->text_size && ov->set_open && ov->button;
}

static float width_of(const OvApi* ov, int font, float size, const char* text)
{
    float width, height;
    ov->text_size(font, size, text, &width, &height);
    return width;
}

/* Cursor positioning is in screen pixels. Register an ImGui item for each
 * hit target so the host handles clipping, pointer ownership and navigation. */
static int header_item(const OvApi* ov, const char* id, float x, float y, float w, float h)
{
    ov->set_cursor_screen_pos(x, y);
    return ov->selectable_ex(id, 0, w, h, 0);
}

static void header(const OvApi* ov, OvPanel* panel, float x, float y, float w, float k, bool stacked)
{
    float height = (stacked ? 95 : 58) * k;
    float label_size = 15 * k;
    int bold = ov->bold_font();
    ov->draw_rect_filled(x, y, x+w, y+height, ov->theme(OV_THEME_PANEL_ALT), 0);
    ov->draw_line(x, y+height, x+w, y+height, ov->theme(OV_THEME_LINE_STRONG), k);
    editor_icon(ov, "logo", x+12*k, y+8*k, 38*k);
    float title_x = x + 60*k;
    ov->draw_text(title_x, y+14*k, ov->theme(OV_THEME_TEXT), bold, 22*k, "DBF");
    title_x += width_of(ov, bold, 22*k, "DBF") + 7*k;
    ov->draw_text(title_x, y+14*k, ov->theme(OV_THEME_ACCENT), bold, 22*k, "REFORGED");

    float tx = stacked ? x+4*k : title_x+width_of(ov,bold,22*k,"REFORGED")+20*k;
    float top = y + (stacked ? 53 : 7)*k;
    float bottom = y+height;
    float available = x+w-tx-(stacked ? 4 : 54)*k;
    float cell = available / VIEW_COUNT;
    for (int i = 0; i < VIEW_COUNT; ++i) {
        float tw = width_of(ov, bold, label_size, labels[i]);
        float item_w = tw + 24*k;
        if (item_w > cell) item_w = cell;
        if (item_w < 1) break;
        ov->push_id_int(i);
        if (header_item(ov, "##view", tx, top, item_w, bottom-top)) view = (enum View)i;
        if (view == (enum View)i) {
            ov->draw_rect_filled(tx, top, tx+item_w, bottom, ov->theme(OV_THEME_ACCENT_DIM), 0);
            ov->draw_rect_filled(tx, bottom-3*k, tx+item_w, bottom, ov->theme(OV_THEME_ACCENT), 0);
        }
        float size = tw > item_w-4*k && tw>0 ? label_size*(item_w-4*k)/tw : label_size;
        if (size > 0) ov->draw_text(tx+(item_w-width_of(ov,bold,size,labels[i]))/2,
            (top+bottom-size)/2, ov->theme(view==(enum View)i ? OV_THEME_ACCENT : OV_THEME_TEXT_DIM),bold,size,labels[i]);
        ov->pop_id();
        tx += item_w;
    }
    ov->set_cursor_screen_pos(x+w-42*k, y+10*k);
    if (ov->button("X##close") && panel) ov->set_open(panel, 0);
}

void editor_shell_draw(const OvApi* ov, const DbfSnapshot* s, const OvFrame* frame, OvPanel* panel)
{
    float x, y, w, h;
    ov->cursor_screen_pos(&x, &y);
    ov->content_region_avail(&w, &h);
    if (w < 1 || h < 1) return;
    float k = frame && frame->scale > 0 ? frame->scale : 1;
    bool stacked = w < 845*k;
    bool search = false;
    bool editing = ov->want_text_input() != 0 || editor_capturing();
    bool focused = !ov->is_focused || ov->is_focused();
    bool escape = focused && !editor_capturing() && ov->key_pressed(0x1b);
    if (escape && view==BROWSE && editor_browse_escape()) escape=false;
    if (!editing && focused) {
        if (ov->key_pressed(0x75) || (ov->key_down(0x10) && ov->key_pressed(0x09))) view = (enum View)((view+1)%VIEW_COUNT);
        if (view != BLACKLIST && ov->key_down(0x11) && ov->key_pressed('F')) { view=BROWSE; search=true; }
        if (ov->key_down(0x11) && ov->key_pressed('E')) view=CHANGES;
        if (s && (view==BROWSE || view==CHANGES) && ov->key_pressed(0x78)) editor_apply_changes(ov,s);
        if (panel && escape) { ov->set_open(panel,0); return; }
    }
    ov->draw_layer(OV_LAYER_WINDOW);
    header(ov, panel, x, y, w, k, stacked);
    float body_y = y + (stacked ? 99 : 62)*k;
    float footer_h = (w < 710*k ? 80 : 50)*k;
    float status_y = y+h-footer_h-34*k;
    float body_h = status_y-body_y;
    ov->set_cursor_screen_pos(x,body_y);
    ov->begin_child("##dbf-editor-body",w,body_h > 1 ? body_h : 1,0);
    if (view != CONTROLS && view != BLACKLIST) editor_page(ov,NULL,false);
    if (!s) ov->text_disabled("Waiting for the first game update");
    else switch (view) {
        case BROWSE: editor_browse(ov,s,search); break;
        case CHANGES: editor_changes(ov,s); break;
        case CONTROLS: case BLACKLIST: editor_page(ov,s,view==BLACKLIST); break;
        case STATUS: ui_status_draw(ov,s); break;
        default: break;
    }
    ov->end_child();
    if (body_h > 0) {
        ov->draw_line(x,status_y+34*k,x+w,status_y+34*k,ov->theme(OV_THEME_LINE_STRONG),k);
        ov->draw_rect_filled(x,status_y,x+w,status_y+34*k,ov->theme(OV_THEME_PANEL_ALT),0);
        ov->draw_line(x,status_y,x+w,status_y,ov->theme(OV_THEME_LINE),k);
        DbfLine state;
        unsigned pending = s ? editor_change_count(s) : 0;
        bool preferences = view == BROWSE || view == CHANGES;
        dbf_line_begin(&state, NULL);
        if (s && s->settings_save_failed) dbf_line_add(&state,"Save failed. Check settings.ini and retry.");
        else if (preferences && pending) {
            dbf_line_add_uint(&state,pending);
            dbf_line_add(&state,pending == 1 ? " pending change" : " pending changes");
        } else if (preferences && s) dbf_line_add(&state,"No pending settings changes");
        else if (view == CONTROLS) dbf_line_add(&state,"Choose an action to change its binding.");
        else if (view == BLACKLIST) dbf_line_add(&state,"Checked stratagems are hidden from selection.");
        else if (s) dbf_line_add(&state,s->hud_owned ? "Native HUD connected" : "Waiting for native HUD");
        ov->draw_text(x+12*k,status_y+7*k,ov->theme(s && s->settings_save_failed ? OV_THEME_DANGER : OV_THEME_TEXT_DIM),
                      1,16*k,state.text);
        ov->set_cursor_screen_pos(x+8*k,status_y+38*k);
        if (view == BROWSE || view == BLACKLIST) {
            ov->key_cap("Ctrl+F"); ov->same_line(); ov->text_disabled("Search");
        } else {
            ov->key_cap("F6"); ov->same_line(); ov->text_disabled("Next view");
        }
        if (s && preferences) {
            if (w >= 710*k) {
                float reserve = width_of(ov,ov->bold_font(),16*k,
                    view == CHANGES ? "RESTORE DEFAULTSDISCARDAPPLY  F9" : "REVIEW CHANGESAPPLY  F9") + 132*k;
                ov->set_cursor_screen_pos(x+w-reserve,status_y+39*k);
            }
            if (view == CHANGES) {
                if (ov->button("RESTORE DEFAULTS")) editor_reset_defaults(s);
                ov->same_line();
                ov->begin_disabled(!pending);
                if (ov->button("DISCARD")) editor_discard_changes();
                ov->end_disabled();
            } else if (ov->button("REVIEW CHANGES")) view = CHANGES;
            ov->same_line();
            ov->begin_disabled(!pending);
            if (ov->button_primary("APPLY  F9")) editor_apply_changes(ov,s);
            ov->end_disabled();
        }
    }
    ov->draw_layer(OV_LAYER_BACKGROUND);
}
