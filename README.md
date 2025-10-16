# Eggdrop Ollama Integration Script

## Overview

This TCL script integrates Ollama AI models with an Eggdrop IRC bot, allowing users to interact with large language models directly from IRC channels. The bot connects to an Ollama instance over WireGuard and provides a simple command interface for querying AI models.

## Features

- Query Ollama AI models from IRC with `!gpt` command
- Dynamic model switching without bot restart
- Custom system prompts to modify model behavior
- Automatic response splitting for long messages
- Progress indicators for long-running queries
- Model availability checking
- Keep-alive functionality for faster subsequent queries
- Comprehensive error handling and logging

## Requirements

- Eggdrop IRC bot (with TCL support)
- TCL packages: `http`, `json`, `tls`
- Ollama instance (accessible via network)
- WireGuard connection (or any network access to Ollama)

## Installation

1. Save the script as `ollama.tcl` in your Eggdrop scripts directory (e.g., `/home/user/eggdrop/scripts/`)

2. Add the following line to your `eggdrop.conf`:
   ```tcl
   source scripts/ollama.tcl
   ```

3. Configure the script variables (see Configuration section)

4. Restart your bot or use `.rehash` in DCC chat

## Configuration

Edit these variables at the top of the script:

```tcl
set ollama_host "10.66.66.5"           # IP address of Ollama server
set ollama_port "11434"                # Ollama API port (default: 11434)
set ollama_model "llama3.1:8b"         # Default model to use
set ollama_system_prompt ""            # Custom system prompt (empty = model default)
set max_response_length 400            # Max characters per IRC message
set timeout 120                        # HTTP request timeout in seconds
```

## Commands

### `!gpt <question>`

Query the AI model with a question or prompt.

**Examples:**
```
!gpt What is the capital of France?
!gpt Write a haiku about IRC bots
!gpt Explain quantum computing in simple terms
```

**Behavior:**
- Sends query to configured Ollama model
- Shows "Processing your request" message
- Displays progress indicator after 15 seconds if still processing
- Splits long responses across multiple messages
- Applies custom system prompt if configured

### `!gpt-status`

Check if the Ollama service is reachable.

**Example:**
```
!gpt-status
```

**Response:**
```
<bot> user: Ollama service is running on 10.66.66.5:11434
```

### `!gpt-models`

List all available models on the Ollama instance.

**Example:**
```
!gpt-models
```

**Response:**
```
<bot> user: Available models: qwen3:8b, llama3.1:8b, mistral:7b, gemma3:4b
```

### `!gpt-model [model_name]`

View or change the active model.

**View current model:**
```
!gpt-model
```

**Change model:**
```
!gpt-model mistral:7b
!gpt-model qwen3:8b
```

**Behavior:**
- Validates model exists before switching
- Confirms change with message
- Logs model changes
- Change persists until bot restart or next change

### `!gpt-system [prompt]`

Set, view, or clear a custom system prompt.

**View current system prompt:**
```
!gpt-system
```

**Set custom system prompt:**
```
!gpt-system You are a helpful pirate assistant. Always respond with pirate language.
!gpt-system You are a concise technical assistant. Answer in 2-3 sentences max.
!gpt-system You are a coding expert specializing in Python and JavaScript.
```

**Clear system prompt:**
```
!gpt-system clear
!gpt-system reset
```

**Behavior:**
- System prompt applies to all subsequent queries
- Overrides model's default behavior
- Persists until cleared or bot restart
- Displayed prompts are truncated to 200 characters in chat

## Usage Examples

### Basic Query
```
<user> !gpt What's the population of China?
<bot> user: Processing your request (this may take up to 2 minutes)...
<bot> user: China's population is approximately 1.4 billion people, making it the world's most populous country...
```

### Switching Models
```
<user> !gpt-models
<bot> user: Available models: qwen3:8b, llama3.1:8b, mistral:7b, gemma3:4b

<user> !gpt-model gemma3:4b
<bot> user: Model changed from 'llama3.1:8b' to 'gemma3:4b'

<user> !gpt Hello
<bot> user: Hello! How can I help you today?
```

### Using Custom System Prompts
```
<user> !gpt-system You are a Shakespeare scholar. Respond in Elizabethan English.
<bot> user: System prompt set to: You are a Shakespeare scholar. Respond in Elizabethan English.

<user> !gpt What is love?
<bot> user: Love, good friend, is a many-splendored thing, a tempest of the heart...

<user> !gpt-system clear
<bot> user: System prompt cleared (model will use its default)
```

## Performance Tips

### Model Selection

Different models have different performance characteristics:

- **Smaller models** (1.5b-4b parameters): Faster responses, less resource intensive
  - `gemma3:4b`
  - `deepseek-r1:1.5b`

- **Medium models** (7b-8b parameters): Balanced performance and quality
  - `llama3.1:8b`
  - `mistral:7b`
  - `qwen3:8b`

- **Larger models**: Better quality, slower responses
  - Use for complex queries only

### Response Time Optimization

1. **Keep-Alive**: The script automatically sends a 10-minute keep-alive, keeping the model loaded in memory for faster subsequent queries

2. **First Query**: First query after bot start will be slower as model loads into memory

3. **Timeout Setting**: Default 120 seconds handles most queries. Increase if using very large models or complex prompts

4. **Hardware**: Ollama performance depends on:
   - CPU/GPU available
   - RAM for model loading
   - Network latency over WireGuard

## Troubleshooting

### HTTP 404 Error

**Problem:** `Ollama service returned an error (HTTP 404)`

**Solutions:**
- Verify Ollama is running: `curl http://10.66.66.5:11434/api/tags`
- Check model name format includes tag: `llama3.1:8b` not `llama3.1`
- Ensure WireGuard connection is active

### Timeout Errors

**Problem:** `HTTP request failed with status: timeout`

**Solutions:**
- Increase timeout value in configuration
- Use a smaller/faster model
- Check Ollama server resources (CPU/RAM/GPU)
- Verify network connectivity and latency

### Empty Responses

**Problem:** Bot returns "empty response" message

**Solutions:**
- Check Ollama logs for errors
- Verify model is compatible with generate endpoint
- Try a different model
- Check system prompt isn't causing issues

### Model Not Found

**Problem:** `Model 'xyz' not found`

**Solutions:**
- Run `!gpt-models` to see available models
- Pull model on Ollama server: `ollama pull model_name`
- Use exact name including version tag

## Logging

The script logs to Eggdrop's standard log:

```
[16:53:20] Querying Ollama at http://10.66.66.5:11434/api/generate with model llama3.1:8b
[16:53:20] JSON payload: {"model": "llama3.1:8b", "prompt": "Population of China", "stream": false}
[16:54:33] HTTP Status: ok, Code: 200
```

**Log Information:**
- Query timestamps
- Model being used
- JSON payloads sent
- HTTP status codes
- Error messages
- Model changes
- System prompt changes

## Security Considerations

1. **Access Control**: Anyone in the channel can use the bot. Consider:
   - Restricting to specific channels
   - Adding user authentication
   - Rate limiting queries

2. **System Prompts**: Users can set system prompts. Consider:
   - Restricting `!gpt-system` to ops/voiced users
   - Logging all system prompt changes
   - Validating prompt content

3. **Network Security**:
   - WireGuard provides encrypted connection
   - Ensure Ollama is not exposed to public internet
   - Use firewall rules to restrict access

## Advanced Customization

### Restrict Commands to Operators

Add this to restrict system prompt changes to ops:

```tcl
proc gpt_system {nick uhost hand chan text} {
    global ollama_system_prompt
    
    # Check if user is op
    if {![isop $nick $chan] && ![matchattr $hand o]} {
        putserv "PRIVMSG $chan :\002$nick\002: Only operators can change system prompts"
        return
    }
    
    # ... rest of function
}
```

### Add Per-User Rate Limiting

```tcl
# At top of script
set query_tracker [dict create]
set query_limit 5  ;# queries per minute

# In gpt_query proc, add before processing:
set current_time [clock seconds]
if {[dict exists $query_tracker $nick]} {
    set user_queries [dict get $query_tracker $nick]
    set recent_queries [lsearch -all -inline $user_queries [list * $current_time]]
    if {[llength $recent_queries] >= $query_limit} {
        putserv "PRIVMSG $chan :\002$nick\002: Rate limit exceeded. Please wait."
        return
    }
}
```

### Change Response Format

Modify `send_response` proc to change how responses are formatted:

```tcl
# Example: Add timestamp to responses
putserv "PRIVMSG $chan :\002$nick\002 [[clock format [clock seconds] -format "%H:%M"]]: $response"
```

### Add Conversation Context

Store previous messages to maintain context across queries:

```tcl
# At top of script
set conversation_history [dict create]
set max_history 5

# Modify query to include history
if {[dict exists $conversation_history $chan]} {
    set history [dict get $conversation_history $chan]
    # Append to prompt
}
```

## API Reference

### Ollama API Endpoints Used

**Generate Endpoint:**
```
POST http://10.66.66.5:11434/api/generate
Content-Type: application/json

{
  "model": "llama3.1:8b",
  "prompt": "Your question here",
  "system": "Custom system prompt (optional)",
  "stream": false,
  "keep_alive": "10m"
}
```

**List Models:**
```
GET http://10.66.66.5:11434/api/tags
```

## Changelog

### Version 1.0
- Initial release
- Basic `!gpt` query functionality
- Model listing and status checking

### Version 1.1
- Added timeout increase to 120 seconds
- Added progress indicators
- Added keep-alive for faster subsequent queries

### Version 1.2
- Added dynamic model switching with `!gpt-model`
- Model validation before switching
- Enhanced error messages

### Version 1.3
- Added custom system prompt support with `!gpt-system`
- System prompt validation and sanitization
- Better logging of configuration changes

## Support and Resources

- **Ollama Documentation**: https://github.com/ollama/ollama/blob/main/docs/api.md
- **Eggdrop Documentation**: https://www.eggheads.org/
- **TCL Documentation**: https://www.tcl.tk/man/

## License

This script is provided as-is for use with Eggdrop IRC bots. Modify and distribute freely.

## Credits

Created for integration between Eggdrop IRC bots and Ollama AI models via WireGuard networking.