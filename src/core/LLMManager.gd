extends HTTPRequest
class_name LLMManager

# This node handles communicating with external LLM APIs.
# It uses a fallback hierarchy: Gemini -> OpenAI -> Claude -> Qwen -> OpenRouter.

signal llm_response_received(response_data: Dictionary)
signal llm_error_occurred(error_message: String)
signal netfeed_stream_received(events: Array)

# Tracks what type of request is active
var current_request_type: String = ""

var active_provider: String = ""
var api_url: String = ""
var api_key: String = ""
var active_model: String = ""

func _ready() -> void:
    self.request_completed.connect(_on_request_completed)
    _initialize_provider()

func _initialize_provider() -> void:
    # Fallback order: Gemini -> OpenAI -> Claude -> Qwen -> OpenRouter -> Local
    
    if not OS.get_environment("GEMINI_API_KEY").is_empty():
        active_provider = "gemini"
        api_key = OS.get_environment("GEMINI_API_KEY")
        # Using Gemini's OpenAI compatibility endpoint for simplicity
        api_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        active_model = "gemini-1.5-pro-latest"
        print("LLMManager: Using Gemini API")
        
    elif not OS.get_environment("OPENAI_API_KEY").is_empty():
        active_provider = "openai"
        api_key = OS.get_environment("OPENAI_API_KEY")
        api_url = "https://api.openai.com/v1/chat/completions"
        active_model = "gpt-4-turbo-preview"
        print("LLMManager: Using OpenAI API")
        
    elif not OS.get_environment("ANTHROPIC_API_KEY").is_empty():
        active_provider = "claude"
        api_key = OS.get_environment("ANTHROPIC_API_KEY")
        api_url = "https://api.anthropic.com/v1/messages"
        active_model = "claude-3-opus-20240229"
        print("LLMManager: Using Claude API")
        
    elif not OS.get_environment("QWEN_API_KEY").is_empty():
        active_provider = "qwen"
        api_key = OS.get_environment("QWEN_API_KEY")
        # Alibaba DashScope OpenAI compatible endpoint
        api_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        active_model = "qwen-max"
        print("LLMManager: Using Qwen API")
        
    elif not OS.get_environment("OPENROUTER_API_KEY").is_empty():
        active_provider = "openrouter"
        api_key = OS.get_environment("OPENROUTER_API_KEY")
        api_url = "https://openrouter.ai/api/v1/chat/completions"
        active_model = "meta-llama/llama-3-70b-instruct" # Reliable fallback model on OpenRouter
        print("LLMManager: Using OpenRouter API")
        
    else:
        # Ultimate fallback: Local inference running on server hardware (Ollama, LMStudio, vLLM)
        active_provider = "local"
        api_key = "local" # Auth not usually required for local loopback
        # Default Ollama / LMStudio OpenAI compatible endpoint
        api_url = OS.get_environment("LOCAL_LLM_URL")
        if api_url.is_empty():
            api_url = "http://127.0.0.1:11434/v1/chat/completions" # Default Ollama host
            
        active_model = OS.get_environment("LOCAL_LLM_MODEL")
        if active_model.is_empty():
            active_model = "llama3" # A safe assumption for a good local model
            
        print("LLMManager: All cloud keys missing. Falling back to LOCAL model at ", api_url)

func request_npc_action(npc: NPCData, player_input: String) -> void:
    if active_provider == "":
        llm_error_occurred.emit("LLM Provider not initialized properly.")
        return
        
    current_request_type = "npc_action"
        
    var headers = [
        "Content-Type: application/json",
        "Authorization: Bearer " + api_key
    ]
    
    if active_provider == "openrouter":
        headers.append("HTTP-Referer: https://killthebill.game")
        headers.append("X-Title: Kill The Bill")
    elif active_provider == "claude":
        headers.append("x-api-key: " + api_key)
        headers.append("anthropic-version: 2023-06-01")
        # Claude uses x-api-key, override Bearer to avoid confusion
        headers[1] = "Authorization: " 
    
    # Construct System Prompt based on WorldDirector state
    var system_prompt = "You are the Game Master for a systemic immersive sim called KILL THE BILL.\n"
    system_prompt += "Evaluate the player's input against the following NPC state:\n"
    system_prompt += npc.get_llm_context_string() + "\n"
    system_prompt += "Respond strictly in JSON format with keys: 'success' (boolean), 'dialogue' (string), and 'assigned_goal' (string: e.g., 'flee', 'attack', 'assist')."

    var payload = {}
    
    if active_provider == "claude":
        # Anthropic specific payload
        payload = {
            "model": active_model,
            "max_tokens": 1024,
            "system": system_prompt,
            "messages": [
                {"role": "user", "content": player_input + "\n\nProvide your response purely in JSON format."}
            ]
        }
    else:
        # Standard OpenAI compatible payload
        payload = {
            "model": active_model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": player_input}
            ],
            "response_format": { "type": "json_object" },
            "temperature": 0.7
        }
    
    var json_payload = JSON.stringify(payload)
    var error = request(api_url, headers, HTTPClient.METHOD_POST, json_payload)
    
    if error != OK:
        llm_error_occurred.emit("Failed to send HTTP Request. Error code: " + str(error))

func request_netfeed_events(world_state: Dictionary, oligarchs: Dictionary) -> void:
    if active_provider == "":
        llm_error_occurred.emit("LLM Provider not initialized properly.")
        return
        
    current_request_type = "netfeed_stream"
    var headers = [
        "Content-Type: application/json",
        "Authorization: Bearer " + api_key
    ]
    if active_provider == "openrouter":
        headers.append("HTTP-Referer: https://killthebill.game")
        headers.append("X-Title: Kill The Bill")
    elif active_provider == "claude":
        headers.append("x-api-key: " + api_key)
        headers.append("anthropic-version: 2023-06-01")
        headers[1] = "Authorization: "
        
    var system_prompt = "You are the Game Master for a systemic immersive sim called KILL THE BILL.\n"
    system_prompt += "Evaluate the complex conjecture of the current world state:\n"
    system_prompt += "Global Economy: " + JSON.stringify(world_state) + "\n"
    system_prompt += "Oligarchs: " + JSON.stringify(oligarchs) + "\n"
    system_prompt += "Based on this state, generate an organic stream of events. The number of events should vary depending on the gravity of the situation.\n"
    system_prompt += "Events can be public news, or invisible systemic shifts that change the world without a headline.\n"
    system_prompt += "Respond STRICTLY in JSON format with a single key 'events' containing an array of objects. Each object must have keys: 'type' (string: 'NEWS_TICKER' or 'SILENT_RIPPLE'), 'headline' (string, can be empty for SILENT_RIPPLE), and 'systemic_impact' (string: briefly describing the numerical or narrative ripple)."
    
    var payload = {}
    if active_provider == "claude":
        payload = {
            "model": active_model,
            "max_tokens": 1024,
            "system": system_prompt,
            "messages": [{"role": "user", "content": "Generate the event stream in JSON."}]
        }
    else:
        payload = {
            "model": active_model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": "Generate the event stream in JSON."}
            ],
            "response_format": { "type": "json_object" },
            "temperature": 0.8
        }
        
    var json_payload = JSON.stringify(payload)
    var error = request(api_url, headers, HTTPClient.METHOD_POST, json_payload)
    if error != OK:
        llm_error_occurred.emit("Failed to send NetFeed Request.")

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
        llm_error_occurred.emit("HTTP Request failed. Response code: " + str(response_code) + " Body: " + body.get_string_from_utf8())
        return
        
    var json = JSON.new()
    var error = json.parse(body.get_string_from_utf8())
    
    if error == OK:
        var data = json.get_data()
        var message_content = ""
        
        # Parse depending on the active provider's structure
        if active_provider == "claude":
            if data.has("content") and data["content"].size() > 0:
                message_content = data["content"][0]["text"]
        else:
            if data.has("choices") and data["choices"].size() > 0:
                message_content = data["choices"][0]["message"]["content"]
                
        if message_content != "":
            var inner_json = JSON.new()
            var parse_error = inner_json.parse(message_content)
            
            if parse_error == OK:
                var parsed_data = inner_json.get_data()
                if current_request_type == "npc_action":
                    llm_response_received.emit(parsed_data)
                elif current_request_type == "netfeed_stream":
                    if parsed_data.has("events"):
                        netfeed_stream_received.emit(parsed_data["events"])
                    else:
                        llm_error_occurred.emit("NetFeed response missing 'events' array.")
            else:
                llm_error_occurred.emit("Failed to parse LLM nested JSON response. Raw content: " + message_content)
        else:
            llm_error_occurred.emit("Unexpected LLM API response format.")
    else:
        llm_error_occurred.emit("Failed to parse API response as JSON.")
