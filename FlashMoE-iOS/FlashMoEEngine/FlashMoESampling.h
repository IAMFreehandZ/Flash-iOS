#ifndef FLASHMOE_SAMPLING_H
#define FLASHMOE_SAMPLING_H

#include "FlashMoEEngine.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define FLASHMOE_REPETITION_HISTORY 512

typedef struct {
    int token;
    double score;
} FlashMoESamplingCandidate;

typedef struct {
    FlashMoESamplingConfig config;
    uint64_t rng_state;
    int rng_initialized;
    int history[FLASHMOE_REPETITION_HISTORY];
    int history_count;
    int history_next;
    FlashMoESamplingCandidate *candidates;
    unsigned char *repeated;
    int capacity;
} FlashMoESampler;

static inline FlashMoESamplingConfig flashmoe_sampling_defaults(void) {
    return (FlashMoESamplingConfig){
        .temperature = 0.7f, .top_p = 0.9f, .top_k = 40, .min_p = 0,
        .repetition_penalty = 1, .repetition_window = 64, .use_seed = 0, .seed = 42
    };
}

static inline float flashmoe_sampling_clamp(float value, float low, float high, float fallback) {
    if (!isfinite(value)) return fallback;
    return value < low ? low : value > high ? high : value;
}

static inline void flashmoe_sampler_init(FlashMoESampler *sampler) {
    memset(sampler, 0, sizeof(*sampler));
    sampler->config = flashmoe_sampling_defaults();
}

static inline void flashmoe_sampler_configure(FlashMoESampler *sampler, FlashMoESamplingConfig config) {
    FlashMoESamplingConfig defaults = flashmoe_sampling_defaults();
    config.temperature = flashmoe_sampling_clamp(config.temperature, 0, 2, defaults.temperature);
    config.top_p = flashmoe_sampling_clamp(config.top_p, 0, 1, defaults.top_p);
    config.min_p = flashmoe_sampling_clamp(config.min_p, 0, 1, defaults.min_p);
    config.repetition_penalty = flashmoe_sampling_clamp(config.repetition_penalty, 1, 2, 1);
    if (config.top_k < 0) config.top_k = 0;
    if (config.repetition_window < 0) config.repetition_window = 0;
    if (config.repetition_window > FLASHMOE_REPETITION_HISTORY) config.repetition_window = FLASHMOE_REPETITION_HISTORY;
    config.use_seed = config.use_seed != 0;
    if (config.use_seed != sampler->config.use_seed || config.seed != sampler->config.seed) {
        sampler->rng_initialized = 0;
    }
    sampler->config = config;
}

static inline void flashmoe_sampler_begin(FlashMoESampler *sampler, uint64_t entropy) {
    if (!sampler->rng_initialized) {
        sampler->rng_state = sampler->config.use_seed ? sampler->config.seed : entropy;
        sampler->rng_initialized = 1;
    }
}

static inline void flashmoe_sampler_reset(FlashMoESampler *sampler, uint64_t entropy) {
    sampler->history_count = 0;
    sampler->history_next = 0;
    sampler->rng_initialized = 0;
    flashmoe_sampler_begin(sampler, entropy);
}

static inline void flashmoe_sampler_accept(FlashMoESampler *sampler, int token) {
    if (token < 0) return;
    sampler->history[sampler->history_next] = token;
    sampler->history_next = (sampler->history_next + 1) % FLASHMOE_REPETITION_HISTORY;
    if (sampler->history_count < FLASHMOE_REPETITION_HISTORY) sampler->history_count++;
}

// SplitMix64 supplies a reproducible stream without global rand()/srand() state.
static inline double flashmoe_sampler_uniform(FlashMoESampler *sampler) {
    uint64_t value = (sampler->rng_state += UINT64_C(0x9e3779b97f4a7c15));
    value = (value ^ (value >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    value = (value ^ (value >> 27)) * UINT64_C(0x94d049bb133111eb);
    value ^= value >> 31;
    return (double)(value >> 11) * 0x1.0p-53;
}

static inline int flashmoe_sampler_reserve(FlashMoESampler *sampler, int count) {
    if (count <= sampler->capacity) return 1;
    FlashMoESamplingCandidate *candidates = malloc((size_t)count * sizeof(*candidates));
    unsigned char *repeated = malloc((size_t)count);
    if (!candidates || !repeated) {
        free(candidates);
        free(repeated);
        return 0;
    }
    free(sampler->candidates);
    free(sampler->repeated);
    sampler->candidates = candidates;
    sampler->repeated = repeated;
    sampler->capacity = count;
    return 1;
}

static inline int flashmoe_sampling_compare(const void *left, const void *right) {
    const FlashMoESamplingCandidate *a = left, *b = right;
    if (a->score != b->score) return a->score > b->score ? -1 : 1;
    return (a->token > b->token) - (a->token < b->token);
}

// Keep the lowest ranked retained candidate at the root of the heap.
static inline void flashmoe_sampling_heap_insert(FlashMoESamplingCandidate *heap, int index) {
    while (index > 0) {
        int parent = (index - 1) / 2;
        if (flashmoe_sampling_compare(&heap[index], &heap[parent]) <= 0) break;
        FlashMoESamplingCandidate temporary = heap[index];
        heap[index] = heap[parent];
        heap[parent] = temporary;
        index = parent;
    }
}

static inline void flashmoe_sampling_heap_replace(FlashMoESamplingCandidate *heap, int count,
                                                 FlashMoESamplingCandidate candidate) {
    heap[0] = candidate;
    int index = 0;
    while (index * 2 + 1 < count) {
        int child = index * 2 + 1;
        if (child + 1 < count && flashmoe_sampling_compare(&heap[child + 1], &heap[child]) > 0) child++;
        if (flashmoe_sampling_compare(&heap[index], &heap[child]) >= 0) break;
        FlashMoESamplingCandidate temporary = heap[index];
        heap[index] = heap[child];
        heap[child] = temporary;
        index = child;
    }
}

// Repetition penalty -> temperature -> top k -> min p -> top p -> random draw.
// Returns -1 for invalid logits or allocation failure. Input logits remain intact.
// The caller records the token after any thinking-budget override.
static inline int flashmoe_sampler_sample(FlashMoESampler *sampler, const float *logits, int count) {
    if (!sampler || !logits || count <= 0) return -1;
    const FlashMoESamplingConfig config = sampler->config;
    int penalize = config.repetition_penalty > 1 && config.repetition_window > 0 && sampler->history_count > 0;
    if ((config.temperature > 0 || penalize) && !flashmoe_sampler_reserve(sampler, count)) return -1;
    if (penalize) {
        memset(sampler->repeated, 0, (size_t)count);
        int recent = config.repetition_window < sampler->history_count ? config.repetition_window : sampler->history_count;
        for (int i = 0; i < recent; i++) {
            int index = (sampler->history_next - 1 - i + FLASHMOE_REPETITION_HISTORY) % FLASHMOE_REPETITION_HISTORY;
            int token = sampler->history[index];
            if (token >= 0 && token < count) sampler->repeated[token] = 1;
        }
    }
    int valid = 0, best = -1;
    int limit = config.top_k > 0 && config.top_k < count ? config.top_k : count;
    double best_score = -INFINITY;
    for (int token = 0; token < count; token++) {
        double score = logits[token];
        if (isnan(score) || score == -INFINITY) continue;
        if (penalize && sampler->repeated[token]) {
            score = score < 0 ? score * config.repetition_penalty : score / config.repetition_penalty;
        }
        if (best < 0 || score > best_score) { best = token; best_score = score; }
        if (config.temperature > 0) {
            FlashMoESamplingCandidate candidate = {token, score};
            if (valid < limit) {
                sampler->candidates[valid] = candidate;
                if (config.top_k > 0) flashmoe_sampling_heap_insert(sampler->candidates, valid);
                valid++;
            } else if (flashmoe_sampling_compare(&candidate, &sampler->candidates[0]) < 0) {
                flashmoe_sampling_heap_replace(sampler->candidates, valid, candidate);
            }
        }
    }
    if (config.temperature == 0 || best < 0) return best;
    qsort(sampler->candidates, (size_t)valid, sizeof(*sampler->candidates), flashmoe_sampling_compare);
    if (config.top_k > 0 && valid > config.top_k) valid = config.top_k;

    double total = 0;
    int retained = 0;
    for (int i = 0; i < valid; i++) {
        double score = sampler->candidates[i].score;
        double weight = best_score == INFINITY ? (score == INFINITY ? 1 : 0)
                                              : exp((score - best_score) / config.temperature);
        // The maximum has weight 1, so min p is a relative cutoff here.
        if (weight < config.min_p) break;
        sampler->candidates[retained++].score = weight;
        total += weight;
    }
    double cumulative = 0;
    int nucleus = 0;
    do {
        cumulative += sampler->candidates[nucleus++].score;
    } while (nucleus < retained && cumulative < config.top_p * total);

    double target = flashmoe_sampler_uniform(sampler) * cumulative;
    double traversed = 0;
    for (int i = 0; i < nucleus; i++) {
        traversed += sampler->candidates[i].score;
        if (target < traversed) return sampler->candidates[i].token;
    }
    return sampler->candidates[nucleus - 1].token;
}

static inline void flashmoe_sampler_free(FlashMoESampler *sampler) {
    free(sampler->candidates);
    free(sampler->repeated);
    sampler->candidates = NULL;
    sampler->repeated = NULL;
    sampler->capacity = 0;
}

#endif
