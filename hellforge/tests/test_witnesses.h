/* A small witness table for the admission tests. admission.c includes this instead of the generated table when
 * DBF_TEST_WITNESSES is defined (a test sets it on its first line: flags: -DDBF_TEST_WITNESSES). It defines the same two
 * symbols as the generated header's DBF_ADDRESSES_DEFINE block, so the test reads the table through the generated
 * header's extern declarations and builds its synthetic game image from it.
 *
 * Shape: two features share alpha (STATE, HUD_READ), HUD_READ has two witnesses (alpha, charlie), charlie spans two
 * 64-byte read chunks, and nothing maps LIST_OPACITY, ENTRY, SCRAMBLE, CAMERA, LATCH, DOCK, WEAPON or TERMINAL. A test
 * that also defines DBF_TEST_LONG_WITNESS gets a fifth witness, echo_…, whose name is 200 bytes long.
 *
 * It also defines the blacklist table (dbf_blacklist_kinds, dbf_blacklist_kind_count) that src/settings.c reads: the
 * generated header declares it extern and admission.c is the one unit that defines it, so every test binary that builds
 * admission.c with this table needs a table here too. Four kinds: 5 hidden by default, 42, 148 and 199 (the largest kind
 * the settings keep) shown by default. */
#ifndef DBF_TEST_WITNESSES_H
#define DBF_TEST_WITNESSES_H

#include <stdint.h>

static const uint8_t tw_alpha[16] = {
    0x48, 0x8b, 0x0d, 0xa3, 0x37, 0x99, 0x02, 0xe8, 0x86, 0x6b, 0x81, 0x00, 0xe8, 0x41, 0x17, 0x7c,
};
static const uint8_t tw_bravo[8] = { 0x44, 0x89, 0x75, 0xd0, 0x49, 0x8d, 0x8f, 0xc0 };
static const uint8_t tw_charlie[100] = {
    0x29, 0xf8, 0x85, 0x12, 0x00, 0x4a, 0xf0, 0xbf, 0xa3, 0x0b, 0x8b, 0xfa, 0x65, 0xd3, 0x30, 0x62,
    0x87, 0x2d, 0xd9, 0xab, 0x2f, 0xb9, 0xd1, 0x80, 0xe3, 0x30, 0x64, 0x95, 0x31, 0x17, 0x66, 0xb8,
    0xf9, 0x63, 0x0e, 0xb9, 0x7d, 0xdc, 0x9b, 0xb6, 0x3d, 0x2d, 0x65, 0x3b, 0x89, 0x9f, 0x64, 0xc2,
    0xf7, 0x72, 0x46, 0x6b, 0x06, 0x60, 0x56, 0x08, 0xaa, 0x9c, 0xbf, 0xc1, 0xc7, 0x94, 0x40, 0xfa,
    0x1b, 0x5e, 0xd8, 0xcb, 0x31, 0xe1, 0x7d, 0x2d, 0xe4, 0xe4, 0xc2, 0x27, 0xda, 0xf1, 0x9b, 0xd1,
    0x2b, 0x62, 0x88, 0xe7, 0xf9, 0x58, 0x09, 0x0b, 0x3f, 0x80, 0xb8, 0x60, 0x83, 0xe7, 0xa8, 0x82,
    0xd2, 0xd7, 0xf8, 0x89,
};
static const uint8_t tw_delta[4] = { 0x41, 0x0f, 0xb6, 0x8e };
#ifdef DBF_TEST_LONG_WITNESS
static const uint8_t tw_echo[4] = { 0x48, 0x83, 0xec, 0x28 };
#endif

const DbfWitness dbf_witnesses[] = {
    { "alpha", 0x100u, 16, (1u << DBF_FEATURE_STATE) | (1u << DBF_FEATURE_HUD_READ), tw_alpha },
    { "bravo", 0x140u, 8, (1u << DBF_FEATURE_STRATAGEMS), tw_bravo },
    { "charlie", 0x200u, 100, (1u << DBF_FEATURE_HUD_READ) | (1u << DBF_FEATURE_POINTING), tw_charlie },
    { "delta", 0x300u, 4, (1u << DBF_FEATURE_SOUND), tw_delta },
#ifdef DBF_TEST_LONG_WITNESS
    /* A 200-byte name, for test_game's reason truncation: it gates STRATAGEMS after bravo, so bravo's reason still
     * comes first when both differ. */
    { "echo_a_witness_name_far_longer_than_any_reason_buffer_a_witn"
      "ess_name_far_longer_than_any_reason_buffer_a_witness_name_fa"
      "r_longer_than_any_reason_buffer_a_witness_name_far_longer_th"
      "an_any_reason_buffer",
      0x380u, 4, (1u << DBF_FEATURE_STRATAGEMS), tw_echo },
#endif
};
const int dbf_witness_count = (int)(sizeof dbf_witnesses / sizeof dbf_witnesses[0]);

const DbfBlacklistKind dbf_blacklist_kinds[] = {
    { 5u, "tw five", true },
    { 42u, "tw forty-two", false },
    { 148u, "tw one-forty-eight", false },
    { 199u, "tw one-ninety-nine", false },
};
const int dbf_blacklist_kind_count = (int)(sizeof dbf_blacklist_kinds / sizeof dbf_blacklist_kinds[0]);

#endif
