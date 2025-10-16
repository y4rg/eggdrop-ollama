#!/usr/bin/env tclsh
# Eggdrop Ollama Integration Script
# Responds to !gpt commands by querying Ollama instance via WireGuard

# Configuration
set ollama_host "10.66.66.5"
set ollama_port "11434"
set ollama_model "llama3.1:8b"  ;# Change this to your preferred model
set ollama_system_prompt ""  ;# Custom system prompt (empty = use model default)
set max_response_length 400  ;# Maximum characters for IRC response
set timeout 120  ;# Timeout in seconds for HTTP requests

# Load required packages
package require http
package require json
package require tls

# Register SSL support for HTTPS if needed
::http::register https 443 [list ::tls::socket -autoservername true]

# Bind the trigger to the procedure
bind pub - "!gpt" gpt_query

# Main procedure to handle !gpt commands
proc gpt_query {nick uhost hand chan text} {
    global ollama_host ollama_port ollama_model ollama_system_prompt max_response_length timeout
    
    # Check if user provided a query
    set query [string trim $text]
    if {$query eq ""} {
        putserv "PRIVMSG $chan :Usage: !gpt <your question>"
        return
    }
    
    # Sanitize the query for JSON
    set query [string map {"\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"} $query]
    
    # Prepare JSON payload for Ollama API (with keep-alive to speed up subsequent queries)
    if {$ollama_system_prompt ne ""} {
        # Sanitize system prompt for JSON
        set sys_prompt [string map {"\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"} $ollama_system_prompt]
        set json_data "{\"model\": \"$ollama_model\", \"prompt\": \"$query\", \"system\": \"$sys_prompt\", \"stream\": false, \"keep_alive\": \"10m\"}"
    } else {
        set json_data "{\"model\": \"$ollama_model\", \"prompt\": \"$query\", \"stream\": false, \"keep_alive\": \"10m\"}"
    }
    
    # Make HTTP request to Ollama
    set url "http://${ollama_host}:${ollama_port}/api/generate"
    
    putlog "Querying Ollama at $url with model $ollama_model"
    putlog "JSON payload: $json_data"
    putserv "PRIVMSG $chan :\002$nick\002: Processing your request (this may take up to 2 minutes)..."
    
    # Start a timer for progress updates on long queries
    set progress_timer [after 15000 [list progress_update $chan $nick]]
    
    # Configure HTTP request
    set headers [list "Content-Type" "application/json" "User-Agent" "EggdropBot/1.0"]
    
    # Set up the HTTP request with error handling
    if {[catch {
        set token [::http::geturl $url \
            -headers $headers \
            -query $json_data \
            -timeout [expr $timeout * 1000] \
            -method POST]
    } error]} {
        after cancel $progress_timer
        putlog "HTTP request failed: $error"
        putserv "PRIVMSG $chan :\002$nick\002: Error connecting to Ollama service."
        return
    }
    
    # Cancel the progress timer since we have a response
    after cancel $progress_timer
    
    # Check HTTP status
    set status [::http::status $token]
    set ncode [::http::ncode $token]
    set response_data [::http::data $token]
    
    putlog "HTTP Status: $status, Code: $ncode"
    putlog "Raw response: [string range $response_data 0 200]..."
    
    if {$status ne "ok" || $ncode != 200} {
        putlog "HTTP request failed with status: $status, code: $ncode"
        putlog "Error response: $response_data"
        putserv "PRIVMSG $chan :\002$nick\002: Ollama service returned an error (HTTP $ncode). Check logs for details."
        ::http::cleanup $token
        return
    }
    
    # Get response data (already retrieved above)
    ::http::cleanup $token
    
    # Parse JSON response
    if {[catch {set response_dict [::json::json2dict $response_data]} error]} {
        putlog "JSON parsing failed: $error"
        putserv "PRIVMSG $chan :\002$nick\002: Invalid response from Ollama service."
        return
    }
    
    # Extract the response text
    if {[dict exists $response_dict "response"]} {
        set ollama_response [dict get $response_dict "response"]
    } else {
        putlog "No 'response' field in Ollama response: $response_data"
        putserv "PRIVMSG $chan :\002$nick\002: Unexpected response format from Ollama."
        return
    }
    
    # Clean up the response
    set ollama_response [string trim $ollama_response]
    
    # Split long responses into multiple messages
    send_response $chan $nick $ollama_response $max_response_length
}

# Helper procedure for progress updates on long queries
proc progress_update {chan nick} {
    putserv "PRIVMSG $chan :\002$nick\002: Still processing... (complex queries can take time)"
}

# Helper procedure to send responses, splitting long messages
proc send_response {chan nick response max_length} {
    # Remove excessive whitespace and newlines
    regsub -all {\s+} $response " " response
    set response [string trim $response]
    
    if {$response eq ""} {
        putserv "PRIVMSG $chan :\002$nick\002: Ollama returned an empty response."
        return
    }
    
    # If response is short enough, send it as one message
    if {[string length $response] <= $max_length} {
        putserv "PRIVMSG $chan :\002$nick\002: $response"
        return
    }
    
    # Split long responses
    set words [split $response " "]
    set current_message ""
    set message_count 1
    
    foreach word $words {
        set potential_message "$current_message $word"
        if {[string length $potential_message] > $max_length} {
            if {$current_message ne ""} {
                putserv "PRIVMSG $chan :\002$nick\002 ($message_count): [string trim $current_message]"
                incr message_count
                set current_message $word
            } else {
                # Single word too long, truncate it
                set truncated [string range $word 0 [expr $max_length - 10]]
                putserv "PRIVMSG $chan :\002$nick\002 ($message_count): ${truncated}..."
                incr message_count
                set current_message ""
            }
        } else {
            set current_message $potential_message
        }
    }
    
    # Send any remaining message
    if {[string trim $current_message] ne ""} {
        putserv "PRIVMSG $chan :\002$nick\002 ($message_count): [string trim $current_message]"
    }
}

# Optional: Add a command to check Ollama status
bind pub - "!gpt-status" gpt_status

proc gpt_status {nick uhost hand chan text} {
    global ollama_host ollama_port timeout
    
    set url "http://${ollama_host}:${ollama_port}/api/tags"
    
    if {[catch {
        set token [::http::geturl $url -timeout [expr $timeout * 1000]]
        set status [::http::status $token]
        set ncode [::http::ncode $token]
        ::http::cleanup $token
        
        if {$status eq "ok" && $ncode == 200} {
            putserv "PRIVMSG $chan :\002$nick\002: Ollama service is running on $ollama_host:$ollama_port"
        } else {
            putserv "PRIVMSG $chan :\002$nick\002: Ollama service unreachable (HTTP $ncode)"
        }
    } error]} {
        putserv "PRIVMSG $chan :\002$nick\002: Cannot connect to Ollama service: $error"
    }
}

# Optional: Add a command to list available models
bind pub - "!gpt-models" gpt_models

# Optional: Add a command to change the current model
bind pub - "!gpt-model" gpt_model

# Optional: Add a command to set/view custom system prompt
bind pub - "!gpt-system" gpt_system

# Optional: Add a command to change the current model
proc gpt_model {nick uhost hand chan text} {
    global ollama_host ollama_port ollama_model timeout
    
    set new_model [string trim $text]
    
    # If no model specified, show current model
    if {$new_model eq ""} {
        putserv "PRIVMSG $chan :\002$nick\002: Current model is: $ollama_model"
        putserv "PRIVMSG $chan :\002$nick\002: Usage: !gpt-model <model_name> (use !gpt-models to see available models)"
        return
    }
    
    # First, let's verify the model exists by checking the models list
    set url "http://${ollama_host}:${ollama_port}/api/tags"
    
    if {[catch {
        set token [::http::geturl $url -timeout [expr $timeout * 1000]]
        set status [::http::status $token]
        set ncode [::http::ncode $token]
        
        if {$status eq "ok" && $ncode == 200} {
            set response_data [::http::data $token]
            if {[catch {set response_dict [::json::json2dict $response_data]} error]} {
                putserv "PRIVMSG $chan :\002$nick\002: Could not verify model availability"
                ::http::cleanup $token
                return
            } else {
                set model_found 0
                if {[dict exists $response_dict "models"]} {
                    set models_list [dict get $response_dict "models"]
                    foreach model $models_list {
                        if {[dict exists $model "name"]} {
                            set model_name [dict get $model "name"]
                            if {$model_name eq $new_model} {
                                set model_found 1
                                break
                            }
                        }
                    }
                }
                
                if {$model_found} {
                    set old_model $ollama_model
                    set ollama_model $new_model
                    putserv "PRIVMSG $chan :\002$nick\002: Model changed from '$old_model' to '$ollama_model'"
                    putlog "Model changed by $nick from '$old_model' to '$ollama_model'"
                } else {
                    putserv "PRIVMSG $chan :\002$nick\002: Model '$new_model' not found. Use !gpt-models to see available models."
                }
            }
        } else {
            putserv "PRIVMSG $chan :\002$nick\002: Could not verify model availability (HTTP $ncode)"
        }
        ::http::cleanup $token
    } error]} {
        putserv "PRIVMSG $chan :\002$nick\002: Error checking model availability: $error"
    }
}

# Optional: Add a command to set/view custom system prompt
proc gpt_system {nick uhost hand chan text} {
    global ollama_system_prompt
    
    set new_prompt [string trim $text]
    
    # If no prompt specified, show current prompt
    if {$new_prompt eq ""} {
        if {$ollama_system_prompt eq ""} {
            putserv "PRIVMSG $chan :\002$nick\002: No custom system prompt set (using model default)"
        } else {
            # Truncate display if too long
            set display_prompt $ollama_system_prompt
            if {[string length $display_prompt] > 200} {
                set display_prompt "[string range $display_prompt 0 196]..."
            }
            putserv "PRIVMSG $chan :\002$nick\002: Current system prompt: $display_prompt"
        }
        putserv "PRIVMSG $chan :\002$nick\002: Usage: !gpt-system <prompt> or !gpt-system clear"
        return
    }
    
    # Handle clearing the prompt
    if {[string tolower $new_prompt] eq "clear" || [string tolower $new_prompt] eq "reset"} {
        set ollama_system_prompt ""
        putserv "PRIVMSG $chan :\002$nick\002: System prompt cleared (model will use its default)"
        putlog "System prompt cleared by $nick"
        return
    }
    
    # Set the new system prompt
    set ollama_system_prompt $new_prompt
    set display_prompt $new_prompt
    if {[string length $display_prompt] > 200} {
        set display_prompt "[string range $display_prompt 0 196]..."
    }
    putserv "PRIVMSG $chan :\002$nick\002: System prompt set to: $display_prompt"
    putlog "System prompt changed by $nick to: $new_prompt"
}

proc gpt_models {nick uhost hand chan text} {
    global ollama_host ollama_port timeout
    
    set url "http://${ollama_host}:${ollama_port}/api/tags"
    
    if {[catch {
        set token [::http::geturl $url -timeout [expr $timeout * 1000]]
        set status [::http::status $token]
        set ncode [::http::ncode $token]
        
        if {$status eq "ok" && $ncode == 200} {
            set response_data [::http::data $token]
            if {[catch {set response_dict [::json::json2dict $response_data]} error]} {
                putserv "PRIVMSG $chan :\002$nick\002: Could not parse models list"
            } else {
                if {[dict exists $response_dict "models"]} {
                    set models_list [dict get $response_dict "models"]
                    set model_names {}
                    foreach model $models_list {
                        if {[dict exists $model "name"]} {
                            lappend model_names [dict get $model "name"]
                        }
                    }
                    if {[llength $model_names] > 0} {
                        putserv "PRIVMSG $chan :\002$nick\002: Available models: [join $model_names ", "]"
                    } else {
                        putserv "PRIVMSG $chan :\002$nick\002: No models found"
                    }
                } else {
                    putserv "PRIVMSG $chan :\002$nick\002: No models list in response"
                }
            }
        } else {
            putserv "PRIVMSG $chan :\002$nick\002: Could not fetch models list (HTTP $ncode)"
        }
        ::http::cleanup $token
    } error]} {
        putserv "PRIVMSG $chan :\002$nick\002: Error fetching models: $error"
    }
}

putlog "Ollama integration script loaded - listening for !gpt commands"
putlog "Ollama host: $ollama_host:$ollama_port, Model: $ollama_model"
if {$ollama_system_prompt ne ""} {
    putlog "Custom system prompt active: [string range $ollama_system_prompt 0 100]..."
}