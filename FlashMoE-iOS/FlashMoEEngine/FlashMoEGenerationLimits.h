#ifndef FLASHMOE_GENERATION_LIMITS_H
#define FLASHMOE_GENERATION_LIMITS_H

#include <stdint.h>

// Reserve one position to close the response before another turn.
static inline int flashmoe_generation_budget(int capacity, int position,
                                             int prompt_tokens, int closing_tokens,
                                             int requested_tokens) {
    if (capacity <= 0 || position < 0 || prompt_tokens <= 0 ||
        closing_tokens < 0 || requested_tokens <= 0) return 0;

    int64_t available = (int64_t)capacity - position - prompt_tokens - closing_tokens - 1;
    if (available <= 0) return 0;
    return available < requested_tokens ? (int)available : requested_tokens;
}

// A positive thinking limit leaves half the output budget available for the answer.
// Zero means unlimited thinking; -1 means insufficient room for the transition
// and answer reserve alongside at least one reasoning token.
static inline int flashmoe_thinking_budget(int configured_tokens, int output_tokens,
                                          int closing_tokens) {
    if (configured_tokens <= 0 || output_tokens <= 0) return 0;
    if (closing_tokens < 1) closing_tokens = 1;
    int budget = output_tokens - output_tokens / 2 - closing_tokens;
    if (budget < 1) return -1;
    return budget < configured_tokens ? budget : configured_tokens;
}

#endif
