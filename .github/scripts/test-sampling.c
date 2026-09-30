#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if __has_include("../../FlashMoE-iOS/FlashMoEEngine/FlashMoESampling.h")
#include "../../FlashMoE-iOS/FlashMoEEngine/FlashMoESampling.h"

static int failures;
static int checks;

#define CHECK(condition, message) do { \
    checks++; \
    if (!(condition)) { fprintf(stderr, "FAIL: %s (line %d)\n", message, __LINE__); failures++; } \
} while (0)

static FlashMoESampler make_sampler(float temperature) {
    FlashMoESampler sampler;
    flashmoe_sampler_init(&sampler);
    FlashMoESamplingConfig config = flashmoe_sampling_defaults();
    config.temperature = temperature;
    config.top_p = 1;
    config.top_k = 0;
    config.min_p = 0;
    config.repetition_penalty = 1;
    config.use_seed = 1;
    config.seed = 42;
    flashmoe_sampler_configure(&sampler, config);
    flashmoe_sampler_reset(&sampler, 123);
    return sampler;
}

static void test_greedy(void) {
    FlashMoESampler sampler = make_sampler(0);
    const float logits[] = {-2, 1, 3, 3};
    for (int i = 0; i < 100; i++) {
        CHECK(flashmoe_sampler_sample(&sampler, logits, 4) == 2,
              "temperature zero selects the maximum and resolves ties by token ID");
    }
    CHECK(memcmp(logits, (float[]){-2, 1, 3, 3}, sizeof(logits)) == 0,
          "sampling does not modify model logits");
    flashmoe_sampler_free(&sampler);
}

static void test_top_k(void) {
    FlashMoESampler sampler = make_sampler(1);
    const float logits[] = {-3, 2, 1, -5};
    sampler.config.top_k = 1;
    for (int i = 0; i < 100; i++) {
        CHECK(flashmoe_sampler_sample(&sampler, logits, 4) == 1, "top k one only keeps the maximum");
    }
    sampler.config.top_k = 2;
    int second_count = 0;
    for (int i = 0; i < 1000; i++) {
        int token = flashmoe_sampler_sample(&sampler, logits, 4);
        CHECK(token == 1 || token == 2, "top k excludes every lower ranked token");
        second_count += token == 2;
    }
    CHECK(second_count > 100, "top k samples more than the maximum");
    sampler.config.top_k = 100;
    CHECK(flashmoe_sampler_sample(&sampler, logits, 4) >= 0, "top k larger than the vocabulary is safe");
    sampler.config.top_k = 2;
    for (int i = 0; i < 100; i++) {
        int token = flashmoe_sampler_sample(&sampler, (float[]){1, 1, 1, 1}, 4);
        CHECK(token == 0 || token == 1, "top k breaks equal-score ties by the lowest token IDs");
    }
    flashmoe_sampler_free(&sampler);
}

static void test_temperature_distribution(void) {
    const float logits[] = {1.098612289f, 0}; // log(3): probabilities 0.75 and 0.25 at T=1.
    const float temperatures[] = {1, 2};
    const double expected[] = {0.75, 0.633974596};
    for (int t = 0; t < 2; t++) {
        FlashMoESampler sampler = make_sampler(temperatures[t]);
        int first_count = 0;
        for (int i = 0; i < 20000; i++) first_count += flashmoe_sampler_sample(&sampler, logits, 2) == 0;
        CHECK(fabs(first_count / 20000.0 - expected[t]) < 0.02,
              "temperature changes the distribution according to softmax");
        flashmoe_sampler_free(&sampler);
    }
}

static void test_probability_filters(void) {
    // Independently chosen probabilities: 0.50, 0.30, 0.20.
    const float logits[] = {-0.693147181f, -1.203972804f, -1.609437912f};
    FlashMoESampler sampler = make_sampler(1);
    sampler.config.top_p = 0.6f;
    int first_count = 0, second_count = 0;
    for (int i = 0; i < 10000; i++) {
        int token = flashmoe_sampler_sample(&sampler, logits, 3);
        CHECK(token == 0 || token == 1, "top p includes the token crossing the cumulative threshold");
        first_count += token == 0;
        second_count += token == 1;
    }
    CHECK(second_count > 2000 && fabs(first_count / 10000.0 - 0.625) < 0.02,
          "top p renormalizes the retained probabilities");
    sampler.config.top_p = 1;
    sampler.config.min_p = 0.7f;
    for (int i = 0; i < 100; i++) {
        CHECK(flashmoe_sampler_sample(&sampler, logits, 3) == 0,
              "min p removes probabilities below its fraction of the maximum");
    }
    sampler.config.min_p = 0.5f;
    sampler.config.top_p = 0.99f;
    sampler.config.top_k = 2;
    second_count = 0;
    for (int i = 0; i < 1000; i++) {
        int token = flashmoe_sampler_sample(&sampler, logits, 3);
        CHECK(token == 0 || token == 1, "top k, top p, and min p combine safely");
        second_count += token == 1;
    }
    CHECK(second_count > 200, "combined filters retain more than one eligible token");
    sampler.config.top_p = 0;
    CHECK(flashmoe_sampler_sample(&sampler, logits, 3) == 0, "a zero probability threshold keeps at least one token");
    flashmoe_sampler_free(&sampler);
}

static void test_repetition(void) {
    FlashMoESampler sampler = make_sampler(0);
    sampler.config.repetition_penalty = 2;
    sampler.config.repetition_window = 2;
    flashmoe_sampler_accept(&sampler, 0);
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){4, 3}, 2) == 1,
          "positive repeated logits are divided by the penalty");
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){-1, -1.5f}, 2) == 1,
          "negative repeated logits are multiplied by the penalty");
    flashmoe_sampler_accept(&sampler, 0);
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){8, 3}, 2) == 0,
          "a repeated token is penalized once even if it appears twice");
    flashmoe_sampler_accept(&sampler, 2);
    flashmoe_sampler_accept(&sampler, 3);
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){4, 3}, 2) == 0,
          "tokens outside the recent repetition window are no longer penalized");
    flashmoe_sampler_accept(&sampler, 0);
    sampler.config.repetition_window = 0;
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){4, 3}, 2) == 0,
          "a zero repetition window disables the penalty");
    sampler.config.repetition_window = 512;
    for (int i = 0; i < 1024; i++) flashmoe_sampler_accept(&sampler, 2);
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){4, 3}, 2) == 0,
          "the history ring discards old tokens when it wraps");
    flashmoe_sampler_reset(&sampler, 555);
    CHECK(sampler.history_count == 0, "a new conversation clears repetition history");
    flashmoe_sampler_free(&sampler);
}

static void test_seed_and_continuation(void) {
    const float logits[] = {0, 0, 0, 0};
    FlashMoESampler first = make_sampler(1), second = make_sampler(1);
    int different = 0;
    for (int i = 0; i < 100; i++) {
        int a = flashmoe_sampler_sample(&first, logits, 4);
        int b = flashmoe_sampler_sample(&second, logits, 4);
        CHECK(a == b, "the same fixed seed reproduces a token sequence");
        if (i == 49) {
            // Applying the same settings before a continuation must keep RNG progress.
            flashmoe_sampler_configure(&first, first.config);
            flashmoe_sampler_begin(&first, 987654);
        }
    }
    flashmoe_sampler_reset(&first, 123);
    flashmoe_sampler_reset(&second, 999);
    CHECK(flashmoe_sampler_sample(&first, logits, 4) == flashmoe_sampler_sample(&second, logits, 4),
          "resetting a fixed seed ignores fresh entropy");
    FlashMoESamplingConfig config = first.config;
    config.use_seed = 0;
    flashmoe_sampler_configure(&first, config);
    flashmoe_sampler_configure(&second, config);
    flashmoe_sampler_reset(&first, 123);
    flashmoe_sampler_reset(&second, 456);
    for (int i = 0; i < 50; i++) {
        different += flashmoe_sampler_sample(&first, logits, 4) != flashmoe_sampler_sample(&second, logits, 4);
    }
    CHECK(different > 0, "fresh random seeds produce different sequences");
    config.use_seed = 1;
    config.seed = 0;
    flashmoe_sampler_configure(&first, config);
    flashmoe_sampler_configure(&second, config);
    flashmoe_sampler_reset(&first, 123);
    flashmoe_sampler_reset(&second, 456);
    for (int i = 0; i < 20; i++) {
        CHECK(flashmoe_sampler_sample(&first, logits, 4) == flashmoe_sampler_sample(&second, logits, 4),
              "zero is a valid fixed seed");
    }
    flashmoe_sampler_accept(&first, 0);
    config = first.config;
    config.seed = 1234;
    config.repetition_penalty = 2;
    flashmoe_sampler_configure(&first, config);
    flashmoe_sampler_begin(&first, 999); // Continuation: no conversation reset.
    second.config = config;
    flashmoe_sampler_reset(&second, 555);
    for (int i = 0; i < 20; i++) {
        CHECK(flashmoe_sampler_sample(&first, logits, 4) == flashmoe_sampler_sample(&second, logits, 4),
              "changing a fixed seed reseeds the next continuation without resetting the chat");
    }
    first.config.temperature = 0;
    CHECK(flashmoe_sampler_sample(&first, (float[]){4, 3}, 2) == 1,
          "changing the seed preserves repetition history");
    flashmoe_sampler_free(&first);
    flashmoe_sampler_free(&second);
}

static void test_invalid_input(void) {
    FlashMoESampler sampler = make_sampler(1);
    FlashMoESamplingConfig config = sampler.config;
    config.temperature = NAN;
    config.top_p = INFINITY;
    config.min_p = -1;
    config.top_k = -5;
    config.repetition_penalty = NAN;
    config.repetition_window = 999999;
    flashmoe_sampler_configure(&sampler, config);
    CHECK(isfinite(sampler.config.temperature) && sampler.config.temperature >= 0 &&
          sampler.config.temperature <= 2 && sampler.config.top_p <= 1 &&
          sampler.config.min_p == 0 && sampler.config.top_k == 0 &&
          isfinite(sampler.config.repetition_penalty) && sampler.config.repetition_window <= 512,
          "invalid saved settings are normalized to supported ranges");
    CHECK(flashmoe_sampler_sample(&sampler, NULL, 4) == -1, "missing logits are rejected");
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){0}, 0) == -1, "empty vocabulary is rejected");
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){NAN, -INFINITY}, 2) == -1,
          "a distribution with no usable logits fails safely");
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){NAN, 2, -INFINITY}, 3) == 1,
          "invalid logits are excluded from sampling");
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){0, INFINITY, -INFINITY}, 3) == 1,
          "positive infinite logits cannot cause a NaN probability");
    flashmoe_sampler_free(&sampler);
}

static void test_large_vocabulary(void) {
    const int count = 248320;
    float *logits = malloc((size_t)count * sizeof(float));
    CHECK(logits != NULL, "large vocabulary fixture allocation");
    if (!logits) return;
    for (int i = 0; i < count; i++) logits[i] = -100;
    logits[count - 1] = 3;
    logits[0] = 2;
    FlashMoESampler sampler = make_sampler(1);
    sampler.config.top_k = 2;
    for (int i = 0; i < 10; i++) {
        int token = flashmoe_sampler_sample(&sampler, logits, count);
        CHECK(token == 0 || token == count - 1, "full Qwen vocabulary preserves token IDs after filtering");
    }
    CHECK(flashmoe_sampler_sample(&sampler, (float[]){0}, 1) == 0,
          "the same sampler can reuse its scratch space for a smaller vocabulary");
    flashmoe_sampler_free(&sampler);
    free(logits);
}

int main(void) {
    test_greedy();
    test_top_k();
    test_temperature_distribution();
    test_probability_filters();
    test_repetition();
    test_seed_and_continuation();
    test_invalid_input();
    test_large_vocabulary();
    if (failures) return 1;
    printf("sampling tests passed (%d checks across 8 behavior groups)\n", checks);
    return 0;
}
#else
int main(void) {
    fputs("FAIL: sampling controls are not implemented; FlashMoESampling.h is missing\n", stderr);
    return 1;
}
#endif
