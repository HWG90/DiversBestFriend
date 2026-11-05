/* text: see text.h. */
#include <stdbool.h>
#include <stddef.h>
#include "kind_names_25480438.h"
#include "text.h"

#define DBF_KIND_NAME_COUNT (sizeof dbf_kind_names / sizeof dbf_kind_names[0])

void dbf_line_begin(DbfLine* l, const char* first)
{
    l->length = 0;
    l->text[0] = '\0';
    dbf_line_add(l, first);
}

void dbf_line_add(DbfLine* l, const char* text)
{
    if (text != NULL)
        for (const char* p = text; *p != '\0' && l->length < DBF_LINE_SIZE - 1; p++) l->text[l->length++] = *p;
    l->text[l->length] = '\0';
}

void dbf_line_add_uint(DbfLine* l, uint32_t value)
{
    char digits[11];
    int n = 0;
    do {
        digits[n++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value != 0);
    while (n > 0 && l->length < DBF_LINE_SIZE - 1) l->text[l->length++] = digits[--n];
    l->text[l->length] = '\0';
}

void dbf_text_copy(char* dst, size_t size, const char* src)
{
    size_t n = 0;
    if (dst == NULL || size == 0) return;
    if (src != NULL)
        while (n < size - 1 && src[n] != '\0') {
            dst[n] = src[n];
            n++;
        }
    dst[n] = '\0';
}

static bool kind_is_named(uint32_t kind)
{
    return kind < DBF_KIND_NAME_COUNT && dbf_kind_names[kind] != NULL;
}

static void line_unnamed(DbfLine* l, uint32_t kind)
{
    dbf_line_begin(l, "Stratagem ");
    dbf_line_add_uint(l, kind);
}

const char* dbf_kind_name(uint32_t kind)
{
    static DbfLine unnamed;
    if (kind_is_named(kind)) return dbf_kind_names[kind];
    line_unnamed(&unnamed, kind);
    return unnamed.text;
}

void dbf_kind_name_copy(uint32_t kind, char* dst, size_t size)
{
    DbfLine l;
    if (kind_is_named(kind)) {
        dbf_text_copy(dst, size, dbf_kind_names[kind]);
        return;
    }
    line_unnamed(&l, kind);
    dbf_text_copy(dst, size, l.text);
}

void dbf_code_arrows(const uint8_t* code, size_t n, char* dst, size_t size)
{
    static const char ARROWS[5] = { '?', '^', '>', 'v', '<' };
    size_t at = 0;
    if (dst == NULL || size == 0) return;
    if (code == NULL) n = 0;
    if (n > DBF_CODE_CAPACITY) n = DBF_CODE_CAPACITY;
    for (size_t i = 0; i < n; i++) {
        if (i > 0 && at < size - 1) dst[at++] = ' ';
        if (at < size - 1) dst[at++] = code[i] >= 1 && code[i] <= 4 ? ARROWS[code[i]] : '?';
    }
    dst[at] = '\0';
}
