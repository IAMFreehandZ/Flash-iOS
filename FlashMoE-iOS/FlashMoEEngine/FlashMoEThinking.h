#ifndef FLASHMOE_THINKING_H
#define FLASHMOE_THINKING_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define FLASHMOE_THINKING_END_TEXT "</think>\n\n"

typedef struct {
    int in_think;
    int think_tokens;
    int closing_index;  // -1 unless a forced transition is being emitted
    int closing_count;
    // ASCII text needs at most one token per byte. Filled by the model tokenizer.
    uint32_t closing_tokens[sizeof(FLASHMOE_THINKING_END_TEXT) - 1];
} FlashMoEThinkingState;

static inline void flashmoe_thinking_state_init(FlashMoEThinkingState *state,
                                               int starts_thinking) {
    memset(state, 0, sizeof(*state));
    state->in_think = starts_thinking;
    state->closing_index = -1;
}

static inline void flashmoe_thinking_accept_token(FlashMoEThinkingState *state,
                                                 int token, int start_token,
                                                 int end_token) {
    if (token == start_token) state->in_think = 1;
    else if (token == end_token) state->in_think = 0;
    else if (state->in_think) state->think_tokens++;
}

// Emit the entire transition through the ordinary decode loop before sampling
// again. Its separator must enter the attention state, token count and stream.
static inline int flashmoe_thinking_forced_token(FlashMoEThinkingState *state,
                                                int budget) {
    if (state->closing_index >= 0 && state->closing_index < state->closing_count) {
        return (int)state->closing_tokens[state->closing_index++];
    }
    state->closing_index = -1;
    if (state->in_think && budget > 0 && state->think_tokens >= budget &&
        state->closing_count > 0) {
        state->closing_index = 1;
        return (int)state->closing_tokens[0];
    }
    return -1;
}

// Qwen3.5's enable_thinking chat-template prefixes. -1 preserves raw/unknown models.
static inline const char *flashmoe_thinking_prefix(int mode) {
    if (mode > 0) return "<think>\n";
    if (mode == 0) return "<think>\n\n</think>\n\n";
    return "";
}

static inline int flashmoe_prompt_ends_with(const char *prompt, const char *suffix) {
    size_t length = strlen(prompt), suffix_length = strlen(suffix);
    return length >= suffix_length && strcmp(prompt + length - suffix_length, suffix) == 0;
}

static inline int flashmoe_prompt_starts_thinking(const char *prompt, int mode) {
    return mode > 0 && prompt &&
        (flashmoe_prompt_ends_with(prompt, "<|im_start|>assistant\n") ||
         flashmoe_prompt_ends_with(prompt, "<|im_start|>assistant\n<think>\n"));
}

// Only complete a chat generation marker. Raw prompts and explicit prefixes keep their text.
static inline char *flashmoe_prompt_with_thinking(const char *prompt, int mode) {
    if (!prompt) return NULL;
    const char *suffix = flashmoe_prompt_ends_with(prompt, "<|im_start|>assistant\n")
        ? flashmoe_thinking_prefix(mode) : "";
    size_t length = strlen(prompt), suffix_length = strlen(suffix);
    if (length > SIZE_MAX - suffix_length - 1) return NULL;
    char *result = malloc(length + suffix_length + 1);
    if (result) {
        memcpy(result, prompt, length);
        memcpy(result + length, suffix, suffix_length + 1);
    }
    return result;
}

static inline char *flashmoe_continuation_prompt(const char *user_content, int mode) {
    if (!user_content) return NULL;
    const char *prefix = "\n<|im_start|>user\n";
    const char *suffix = "<|im_end|>\n<|im_start|>assistant\n";
    const char *thinking = flashmoe_thinking_prefix(mode);
    size_t prefix_length = strlen(prefix), user_length = strlen(user_content);
    size_t suffix_length = strlen(suffix), thinking_length = strlen(thinking);
    size_t overhead = prefix_length + suffix_length + thinking_length + 1;
    if (user_length > SIZE_MAX - overhead) return NULL;
    char *result = malloc(user_length + overhead);
    if (result) {
        char *cursor = result;
        memcpy(cursor, prefix, prefix_length); cursor += prefix_length;
        memcpy(cursor, user_content, user_length); cursor += user_length;
        memcpy(cursor, suffix, suffix_length); cursor += suffix_length;
        memcpy(cursor, thinking, thinking_length + 1);
    }
    return result;
}

#endif
