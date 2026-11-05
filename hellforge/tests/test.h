/* A minimal test runner: CHECK prints PASS or FAIL for one condition and counts the failures; end main with
 * TEST_MAIN_END so the binary's exit code is the number of failures (build.sh test reports any non-zero exit). */
#ifndef DBF_TEST_H
#define DBF_TEST_H

#include <stdio.h>

static int g_test_failures;

#define CHECK(cond, text) \
    do { \
        if (cond) { \
            printf("PASS %s\n", (text)); \
        } else { \
            printf("FAIL %s (%s:%d)\n", (text), __FILE__, __LINE__); \
            g_test_failures++; \
        } \
    } while (0)

static inline int test_failures(void) { return g_test_failures; }

/* An exit code is one byte, so a count that would wrap to 0 stays 255. */
#define TEST_MAIN_END return g_test_failures > 255 ? 255 : g_test_failures;

#endif
