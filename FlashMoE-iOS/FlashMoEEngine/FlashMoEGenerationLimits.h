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
    if (available < requested_tokens) return 0;
    return requested_tokens;
}

#endif
