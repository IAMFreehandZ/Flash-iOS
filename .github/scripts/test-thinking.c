#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../FlashMoE-iOS/FlashMoEEngine/FlashMoEThinking.h"
#include "../../FlashMoE-iOS/FlashMoEEngine/FlashMoEGenerationLimits.h"

static int failures;

static void check_prompt(const char *name, const char *prompt, int mode,
                         const char *expected, int starts_thinking) {
    char *actual = flashmoe_prompt_with_thinking(prompt, mode);
    if (!actual || strcmp(actual, expected) != 0) {
        fprintf(stderr, "FAIL: %s: unexpected generation prompt\n", name);
        failures++;
    }
    if (flashmoe_prompt_starts_thinking(prompt, mode) != starts_thinking) {
        fprintf(stderr, "FAIL: %s: incorrect initial thinking state\n", name);
        failures++;
    }
    free(actual);
}

int main(void) {
    const char *prompt = "<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n";
    check_prompt("thinking opens in the prompt", prompt, 1,
                 "<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n<think>\n", 1);
    check_prompt("off closes thinking before the first sampled token", prompt, 0,
                 "<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n", 0);
    check_prompt("unknown models retain their original prompt", prompt, -1, prompt, 0);
    check_prompt("raw text remains raw", "Complete this sentence: ", 1,
                 "Complete this sentence: ", 0);
    check_prompt("an existing thinking prefix is not duplicated",
                 "<|im_start|>assistant\n<think>\n", 1,
                 "<|im_start|>assistant\n<think>\n", 1);
    check_prompt("an already closed block is not reopened",
                 "<|im_start|>assistant\n<think>\n\n</think>\n\n", 1,
                 "<|im_start|>assistant\n<think>\n\n</think>\n\n", 0);

    char *on_turn = flashmoe_continuation_prompt("Next question", 1);
    char *off_turn = flashmoe_continuation_prompt("Next question", 0);
    if (!on_turn || strcmp(on_turn,
        "\n<|im_start|>user\nNext question<|im_end|>\n<|im_start|>assistant\n<think>\n") != 0) {
        fputs("FAIL: continuation does not open thinking\n", stderr);
        failures++;
    }
    if (!off_turn || strcmp(off_turn,
        "\n<|im_start|>user\nNext question<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n") != 0) {
        fputs("FAIL: continuation does not turn thinking off\n", stderr);
        failures++;
    }
    free(on_turn);
    free(off_turn);

    // Even at the default output limit, each preset has a distinct effective budget.
    if (flashmoe_thinking_budget(128, 2048) != 128 ||
        flashmoe_thinking_budget(512, 2048) != 512 ||
        flashmoe_thinking_budget(2048, 2048) != 1023) {
        fputs("FAIL: thinking presets do not preserve the answer reserve\n", stderr);
        failures++;
    }
    if (failures) return 1;
    puts("thinking tests passed (prompt modes, continuation switches, answer reserve)");
    return 0;
}
