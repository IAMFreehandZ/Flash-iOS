#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../FlashMoE-iOS/FlashMoEEngine/FlashMoEThinking.h"
#include "../../FlashMoE-iOS/FlashMoEEngine/FlashMoEGenerationLimits.h"

static int failures;

#define CHECK(condition, message) do { \
    if (!(condition)) { fprintf(stderr, "FAIL: %s\n", message); failures++; } \
} while (0)

enum { START = 1001, END = 1002, SEPARATOR = 7, TEXT = 42 };

static FlashMoEThinkingState thinking_state(int starts_thinking) {
    FlashMoEThinkingState state;
    flashmoe_thinking_state_init(&state, starts_thinking);
    state.closing_tokens[0] = END;
    state.closing_tokens[1] = SEPARATOR;
    state.closing_count = 2;
    return state;
}

static void accept(FlashMoEThinkingState *state, int token) {
    flashmoe_thinking_accept_token(state, token, START, END);
}

static void test_budget_transition(void) {
    // The opening marker is prefilled on both fresh and cached chat turns.
    FlashMoEThinkingState state = thinking_state(1);
    for (int i = 0; i < 1022; i++) {
        CHECK(flashmoe_thinking_forced_token(&state, 1022) == -1,
              "thinking stays open until the reasoning budget is consumed");
        accept(&state, TEXT);
    }
    CHECK(flashmoe_thinking_forced_token(&state, 1022) == END,
          "the budget forces the end marker");
    accept(&state, END);
    CHECK(!state.in_think, "the end marker closes thinking");
    CHECK(flashmoe_thinking_forced_token(&state, 1022) == SEPARATOR,
          "the answer separator is forced before sampling resumes");
    accept(&state, SEPARATOR);
    CHECK(state.think_tokens == 1022, "transition tokens are outside the reasoning budget");
    CHECK(flashmoe_thinking_forced_token(&state, 1022) == -1,
          "sampling resumes only after the full transition");
    CHECK(strcmp(FLASHMOE_THINKING_END_TEXT, "</think>\n\n") == 0,
          "the forced transition uses Qwen's answer boundary");
}

static void test_natural_end_and_unlimited(void) {
    FlashMoEThinkingState state = thinking_state(1);
    accept(&state, TEXT);
    accept(&state, END);
    CHECK(flashmoe_thinking_forced_token(&state, 1) == -1,
          "a natural end is not replaced by a forced transition");
    accept(&state, TEXT);
    CHECK(state.think_tokens == 1, "answer tokens do not count as reasoning");

    state = thinking_state(1);
    for (int i = 0; i < 4096; i++) {
        accept(&state, TEXT);
        CHECK(flashmoe_thinking_forced_token(&state, 0) == -1,
              "unlimited reasoning is never closed by a separate budget");
    }
}

static void test_generated_open_and_multiple_separator_tokens(void) {
    FlashMoEThinkingState state = thinking_state(0);
    accept(&state, TEXT);
    CHECK(state.think_tokens == 0, "direct answer text is outside thinking");
    accept(&state, START);
    CHECK(state.think_tokens == 0, "the opening marker is outside the reasoning budget");
    accept(&state, TEXT);
    state.closing_tokens[1] = 8;
    state.closing_tokens[2] = 9;
    state.closing_count = 3;
    CHECK(flashmoe_thinking_forced_token(&state, 1) == END, "generated thinking can be limited");
    accept(&state, END);
    CHECK(flashmoe_thinking_forced_token(&state, 1) == 8, "the first separator token is queued");
    accept(&state, 8);
    CHECK(flashmoe_thinking_forced_token(&state, 1) == 9, "the entire encoded separator is queued");
    accept(&state, 9);
    CHECK(flashmoe_thinking_forced_token(&state, 1) == -1, "the queue drains completely");
    accept(&state, START);
    CHECK(flashmoe_thinking_forced_token(&state, 1) == END,
          "reopening thinking does not reset the per-reply budget");
}

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
    if (flashmoe_thinking_budget(128, 2048, 2) != 128 ||
        flashmoe_thinking_budget(512, 2048, 2) != 512 ||
        flashmoe_thinking_budget(2048, 2048, 2) != 1022 ||
        flashmoe_thinking_budget(2048, 2048, 3) != 1021) {
        fputs("FAIL: thinking presets must reserve the closing tag AND answer separator\n", stderr);
        failures++;
    }
    test_budget_transition();
    test_natural_end_and_unlimited();
    test_generated_open_and_multiple_separator_tokens();
    if (failures) return 1;
    puts("thinking tests passed (prompt modes, continuation switches, answer reserve, forced transitions)");
    return 0;
}
