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
output for the answer and the complete tokenized `</think>\n\n` transition. With a 2,048-token output
limit and sufficient context, Low allows 128 thinking tokens, Medium 512, and High
1,022 when that transition encodes as two tokens. The engine uses the loaded
tokenizer's actual transition length. Unlimited can spend the entire output on thinking.
If a cached turn cannot fit the transition and answer reserve, the chat retries
with a full prompt. An oversized full prompt reports insufficient context space.

When a limit is reached, the closing tag and separator pass through the same
generation loop, attention state, sampling history, and callback stream as other
output tokens. Sampling resumes after the separator has been consumed by the model.
The display parser keeps every marked thinking block in the disclosure, including
a block reopened after an answer starts and an unfinished block at the output limit.
Markers split across streaming callbacks are held until they are complete.

Settings are saved automatically and copied at the start of a reply. Changes
during generation apply to the next reply without reloading or clearing the cache.
The opening thinking marker is prefilled and restored in the displayed message so
the existing thinking disclosure continues to work.

## Automated checks

Compile and run `.github/scripts/test-thinking.c` with a C11 compiler. It checks
the actual prompt helper for thinking on/off, raw and unknown prompts, existing
prefixes, cached turn prefixes, the answer reserve, natural and forced transitions,
Unlimited, and separators that encode as multiple tokens. The IPA workflow also
runs it with address and undefined-behavior sanitizers.

`ThinkingSettingsTests` covers model capabilities, saved choices, the default
budget, invalid preferences, Off versus Unlimited, raw mode, reply snapshots,
long and reopened thinking blocks, incomplete blocks, split markers, and marker order.
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

## Issue #5 device regression

Use Max Output Tokens 2,048, Context Window 4,096, and Thinking High. Reload the
model after changing Context Window. Start a new chat and ask for a short story.
Expand the thinking disclosure and observe the transition near the effective
thinking budget. The model should transition to the story after the full answer
separator; any newly marked thinking must stay in the disclosure. Repeat with a
follow-up in the same chat to exercise the cached continuation path.

Also try Thinking Unlimited with the same output and context settings. Reasoning
should stay in the disclosure beyond 1,000 tokens until its natural closing marker
or the overall output limit. Stop a reply during thinking and confirm its partial
reasoning stays in the disclosure. Then try Low and Off on successive replies.

These automated tests verify token routing and parsing without running a Qwen
model. Device testing must establish whether the model produces a final answer
after the forced transition. Untagged planning text after a valid closing marker
cannot be identified reliably by the parser. Repetitive planning is deferred for
a separate engine/model investigation, as requested.
