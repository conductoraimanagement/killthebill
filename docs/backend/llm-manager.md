# LLMManager — Technical Reference

## Overview
`LLMManager.gd` is the game's network interface to external AI. It extends `HTTPRequest` and handles all communication with LLM providers for NPC dialogue generation and NetFeed event streaming.

**Script:** `src/core/LLMManager.gd`  
**Extends:** `HTTPRequest` (Autoload Singleton)

## Provider Fallback Hierarchy
On `_ready()`, the manager scans `OS.get_environment()` for API keys. The first available provider is selected:

| Priority | Provider | Env Variable | Default Model | Endpoint |
|---|---|---|---|---|
| 1 | Gemini | `GEMINI_API_KEY` | `gemini-1.5-pro-latest` | googleapis.com (OpenAI compat) |
| 2 | OpenAI | `OPENAI_API_KEY` | `gpt-4-turbo-preview` | api.openai.com |
| 3 | Claude | `ANTHROPIC_API_KEY` | `claude-3-opus-20240229` | api.anthropic.com |
| 4 | Qwen | `QWEN_API_KEY` | `qwen-max` | dashscope.aliyuncs.com |
| 5 | OpenRouter | `OPENROUTER_API_KEY` | `llama-3-70b-instruct` | openrouter.ai |
| 6 | Local | `LOCAL_LLM_URL` (optional) | `llama3` or `LOCAL_LLM_MODEL` | 127.0.0.1:11434 |

## Provider-Specific Adaptations
- **OpenAI-compatible** (Gemini, OpenAI, Qwen, OpenRouter, Local): Standard `messages` array + `model` + optional `response_format`.
- **Claude**: Separate `system` top-level string. Requires `max_tokens`. Uses `x-api-key` header. Needs `anthropic-version` header.
- **OpenRouter**: Standard format + `HTTP-Referer` and `X-Title` headers.

## Request Functions
### `request_npc_action(npc: NPCData, player_input: String)`
Generates contextual NPC dialogue. Builds system prompt from `NPCData.get_llm_context_string()` + WorldDirector state. Emits `llm_response_received(parsed_data)`.

### `request_netfeed_events(world_state: Dictionary, oligarchs: Dictionary)`
Evaluates the complex conjecture. Instructs the LLM to generate an organic, uncapped stream of NEWS_TICKER and SILENT_RIPPLE events. Emits `netfeed_stream_received(events_array)`.

## Signals
| Signal | Payload | When |
|---|---|---|
| `llm_response_received` | Dictionary | NPC action response parsed |
| `netfeed_stream_received` | Array | NetFeed event stream parsed |
| `llm_error_occurred` | String | HTTP failure or parse error |

## Response Parsing
`_on_request_completed()` extracts `message.content` from JSON, parses as nested JSON, and routes based on `current_request_type` ("npc_action" or "netfeed_stream").
