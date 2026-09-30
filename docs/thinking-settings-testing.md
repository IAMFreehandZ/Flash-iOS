# Thinking settings

Qwen3.5 supports thinking On/Off through its generation prefix, as documented in
[the model card](https://huggingface.co/Qwen/Qwen3.5-35B-A3B) and
[the official chat template](https://huggingface.co/Qwen/Qwen3.5-35B-A3B/blob/main/chat_template.jinja).
Low, Medium, and High are app presets for the engine's thinking token limit.

| Setting | Thinking token limit |
| --- | --- |
| Off | Thinking block closed in the prompt before generation |
| Low | 128 |
| Medium | 512 |
| High (default) | 2,048 |
| Unlimited | No separate limit; Max Output Tokens still applies |

The app identifies supported models from `config.json` (`qwen3_5_moe` or
`qwen3_5_moe_text`), rather than the directory name. Unknown model types retain
their original prompt and have no thinking choices in chat. The model screen
offers Qwen3.5 settings before a model is installed, matching the curated catalog.
Thinking controls require Chat Template to be enabled.

For limited thinking, the effective budget is capped to reserve half the remaining
output for the answer and one token to close thinking. With a 2,048-token output
limit and sufficient context, Low allows 128 thinking tokens, Medium 512, and High
1,023. Unlimited can spend the entire output on thinking.

Settings are saved automatically and copied at the start of a reply. Changes
during generation apply to the next reply without reloading or clearing the cache.
The opening thinking marker is prefilled and restored in the displayed message so
the existing thinking disclosure continues to work.

## Automated checks

Compile and run `.github/scripts/test-thinking.c` with a C11 compiler. It checks
the actual prompt helper for thinking on/off, raw and unknown prompts, existing
prefixes, cached turn prefixes, and the answer reserve. The IPA workflow also
runs it with address and undefined-behavior sanitizers.

`ThinkingSettingsTests` covers model capabilities, saved choices, the default
budget, invalid preferences, Off versus Unlimited, raw mode, and reply snapshots.
`ThinkingSettingsUITests` checks available options and Off persistence across
relaunch. Both targets are included in the existing simulator test workflow.

## Device checks with a Qwen3.5 MoE model

1. In Models & Settings, choose High and load the model. Ask a question that needs
   several steps. Verify the thinking disclosure streams and the final answer
   appears within the output limit.
2. Choose Off in the chat menu and send another question in the same chat. Verify
   the reply appears directly, with no thinking disclosure. Context usage should
   continue from the preceding turn rather than reset.
3. Switch to Low, then Medium, then High on successive questions. Check that the
   logged thinking budget changes (128, 512, and up to 2,048); a small remaining
   context or output limit may reduce it.
4. Change the setting during a reply. Verify that reply keeps its initial setting
   and the next reply adopts the new setting.
5. Fill the context until continuation falls back to a full prompt. Verify Off
   remains Off, and enabled thinking still appears in the thinking disclosure.
6. Relaunch the app and verify the saved choice. Disable Chat Template, verify the
   thinking picker is disabled, and check that raw text is sent without a Qwen
   thinking prefix on both the first and subsequent messages.
