#include <limits.h>
#include <stdio.h>
#include "../../FlashMoE-iOS/FlashMoEEngine/FlashMoEGenerationLimits.h"

int main(void) {
    const struct {
        const char *name;
        int capacity, position, prompt, closing, requested, expected;
    } cases[] = {
        {"fresh response exceeds 500 tokens", 4096, 0, 64, 0, 2048, 2048},
        {"continuation exceeds 500 tokens", 8192, 2200, 64, 2, 2048, 2048},
        {"fresh response fits a smaller context", 2048, 0, 40, 0, 2048, 2007},
        {"continuation reserves pending and closing tokens", 4096, 3000, 70, 2, 2048, 1023},
        {"completed turn reserves its pending EOS", 4096, 3000, 70, 1, 2048, 1024},
        {"one output token still reserves a closing token", 16, 0, 14, 0, 2048, 1},
        {"full context requires reset", 4096, 4000, 100, 2, 2048, 0},
        {"oversized prompt cannot generate", 2048, 0, 2048, 0, 2048, 0},
        {"empty prompt is rejected", 4096, 0, 0, 0, 2048, 0},
        {"zero output is rejected", 4096, 0, 64, 0, 0, 0},
        {"negative position is rejected", 4096, -1, 64, 0, 2048, 0},
        {"large values cannot overflow into free space", INT_MAX, INT_MAX, INT_MAX, 2, 2048, 0},
    };
    int failures = 0;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        int actual = flashmoe_generation_budget(cases[i].capacity, cases[i].position,
                                               cases[i].prompt, cases[i].closing,
                                               cases[i].requested);
        if (actual != cases[i].expected) {
            fprintf(stderr, "FAIL: %s: expected %d, got %d\n",
                    cases[i].name, cases[i].expected, actual);
            failures++;
        }
    }
    const struct {
        const char *name;
        int configured, output, expected;
    } thinking_cases[] = {
        {"larger output leaves 1024 tokens for an answer", 2048, 2048, 1023},
        {"legacy 500-token output keeps its answer reserve", 2048, 500, 249},
        {"configured thinking limit remains an upper bound", 64, 2048, 64},
        {"large output honors configured thinking limit", 2048, 8192, 2048},
        {"zero thinking budget remains unlimited", 0, 2048, 0},
        {"short response keeps half its tokens for the answer", 2048, 64, 31},
    };
    for (size_t i = 0; i < sizeof(thinking_cases) / sizeof(thinking_cases[0]); i++) {
        int actual = flashmoe_thinking_budget(thinking_cases[i].configured,
                                              thinking_cases[i].output);
        if (actual != thinking_cases[i].expected) {
            fprintf(stderr, "FAIL: %s: expected %d, got %d\n",
                    thinking_cases[i].name, thinking_cases[i].expected, actual);
            failures++;
        }
    }
    if (failures) return 1;
    puts("generation limit tests passed (12 context cases, 6 thinking cases)");
    return 0;
}
