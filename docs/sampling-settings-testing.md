# Sampling settings device testing

Use the unsigned IPA produced by the **Build unsigned LiveContainer IPA** workflow on `codex/sampling-settings`. Import it into LiveContainer as usual.

GitHub Actions runs the C sampler with AddressSanitizer and UndefinedBehaviorSanitizer, the existing context and packaging tests, a device build with static analysis, and settings unit tests and UI tests in an iPhone simulator. The simulator tests require no model files. Generation with a real model and performance on iPhone require device testing.

1. Open the model screen and find **Sampling Settings**. Change temperature, top p, top k, min p, repetition penalty/window, and the fixed seed. Restart the app and check that they remain saved. **Reset Sampling Settings** should restore every control.
2. Load a normal model, reset sampling settings, and ask an open prompt such as “Invent six unusual names for a coffee shop and explain each.” Repeat in several new chats. Replies should vary with fresh randomness; a single repeated answer can still occur by chance.
3. Set temperature to **0**, repetition penalty to **1**, and repeat the same prompt in new chats. Responses should be stable. Probability filters and seed controls should be visibly inactive.
4. Set temperature to **0.7**, enable **Use Fixed Seed**, and use seed **42**. Repeat an identical prompt in new chats with the same model and settings. The sampling sequence should repeat. Check that **0** is also accepted as a seed, then turn fixed seed off and check for variation again.
5. In an existing conversation, open **Sampling Settings** from the chat menu, change a setting, tap **Done**, and send a follow-up. The change should apply without losing the conversation or reloading the model. Changing settings while a reply is running should affect the next reply.
6. Exercise top k **1**, top k **0**, top p **1**, min p **0**, and a repetition penalty above **1**. Confirm that replies remain readable, finish normally, honor output/context limits, and can be cancelled. Check follow-ups and a chat that reaches its context limit.

Compare tokens per second and memory against the previous build with the same model. Record the model, quantization, settings, prompt, and any crash or unexpected output.
