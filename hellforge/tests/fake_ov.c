/* fake_ov: see fake_ov.h. */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include "fake_ov.h"

#define LOG_LINES 1024
#define LINE_SIZE 256
#define STACK_SIZE 32

static char g_log[LOG_LINES][LINE_SIZE];
static int g_count;
static int g_overflowed;
static int g_result_bar = 1, g_result_item = 1, g_result_table = 1;
static char g_stack[STACK_SIZE]; /* 'B' tab bar, 'I' tab item, 'T' table */
static int g_depth;
static int g_misuse;

static void add(const char* prefix, const char* text)
{
    if (g_count >= LOG_LINES) {
        g_overflowed = 1;
        return;
    }
    snprintf(g_log[g_count++], LINE_SIZE, "%s%s", prefix, text ? text : "(null)");
}

static int begin(char kind, int result)
{
    if (!result) return 0;
    if (g_depth < STACK_SIZE) g_stack[g_depth] = kind;
    g_depth++;
    return 1;
}

static void end(char kind)
{
    if (g_depth <= 0 || (g_depth <= STACK_SIZE && g_stack[g_depth - 1] != kind)) g_misuse++;
    if (g_depth > 0) g_depth--;
}

static void f_text(const char* text) { add("text:", text); }
static void f_text_colored(uint32_t color, const char* text) { (void)color; add("text_colored:", text); }
static void f_text_disabled(const char* text) { add("text_disabled:", text); }
static void f_text_wrapped(const char* text) { add("text_wrapped:", text); }
static void f_separator(void) { add("separator", ""); }
static void f_spacing(void) { add("spacing", ""); }

static int f_begin_tab_bar(const char* id)
{
    add("tabbar:", id);
    return begin('B', g_result_bar);
}
static void f_end_tab_bar(void)
{
    add("end:tabbar", "");
    end('B');
}
static int f_begin_tab_item(const char* label)
{
    add("tab:", label);
    return begin('I', g_result_item);
}
static void f_end_tab_item(void)
{
    add("end:tab", "");
    end('I');
}
static int f_begin_table(const char* id, int columns)
{
    (void)columns;
    add("table:", id);
    return begin('T', g_result_table);
}
static void f_table_setup_column(const char* label) { add("col:", label); }
static void f_table_headers_row(void) { add("headers", ""); }
static void f_table_next_row(void) { add("row", ""); }
static int f_table_next_column(void)
{
    add("cell", "");
    return 1;
}
static void f_end_table(void)
{
    add("end:table", "");
    end('T');
}

static const OvApi g_api = {
    .version = 4,
    .size = sizeof(OvApi),
    .text = f_text,
    .text_colored = f_text_colored,
    .text_disabled = f_text_disabled,
    .text_wrapped = f_text_wrapped,
    .separator = f_separator,
    .spacing = f_spacing,
    .begin_tab_bar = f_begin_tab_bar,
    .end_tab_bar = f_end_tab_bar,
    .begin_tab_item = f_begin_tab_item,
    .end_tab_item = f_end_tab_item,
    .begin_table = f_begin_table,
    .table_setup_column = f_table_setup_column,
    .table_headers_row = f_table_headers_row,
    .table_next_row = f_table_next_row,
    .table_next_column = f_table_next_column,
    .end_table = f_end_table,
};

const OvApi* fake_ov_api(void) { return &g_api; }

void fake_ov_reset(void)
{
    g_count = 0;
    g_overflowed = 0;
    g_depth = 0;
    g_misuse = 0;
    g_result_bar = g_result_item = g_result_table = 1;
}

void fake_ov_set_results(int tab_bar, int tab_item, int table)
{
    g_result_bar = tab_bar;
    g_result_item = tab_item;
    g_result_table = table;
}

int fake_ov_lines(void) { return g_count; }

const char* fake_ov_line(int index)
{
    return index >= 0 && index < g_count ? g_log[index] : NULL;
}

int fake_ov_find(const char* line, int from)
{
    for (int i = from < 0 ? 0 : from; i < g_count; i++)
        if (strcmp(g_log[i], line) == 0) return i;
    return -1;
}

int fake_ov_count_prefix(const char* prefix)
{
    int n = 0;
    size_t length = strlen(prefix);
    for (int i = 0; i < g_count; i++)
        if (strncmp(g_log[i], prefix, length) == 0) n++;
    return n;
}

int fake_ov_overflowed(void) { return g_overflowed; }
int fake_ov_open(void) { return g_depth; }
int fake_ov_misuse(void) { return g_misuse; }
