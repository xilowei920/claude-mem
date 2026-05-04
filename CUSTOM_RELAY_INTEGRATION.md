# Claude-Mem Custom API Relay Integration Guide

## Overview

This guide explains how to integrate claude-mem with custom OpenAI-compatible API endpoints (like LiteLLM, local proxies, or third-party model providers) without modifying the core claude-mem source code.

## Architecture

```
claude-mem
  ↓
Local Relay / LiteLLM / Custom Proxy
  ↓
Third-party Model API (OpenAI-compatible)
  ↓
DeepSeek / Qwen / Mistral / Ollama / etc.
```

## Implementation Options

### Option 1: Use OpenRouter with Custom Base URL (Minimal Change)

Modify the OpenRouter provider to point to your local relay:

**Environment Variable:**
```bash
export CLAUDE_MEM_OPENROUTER_BASE_URL="http://127.0.0.1:4000/v1"
```

**Settings File (~/.claude-mem/settings.json):**
```json
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "test-key",
  "CLAUDE_MEM_OPENROUTER_MODEL": "mem-model",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

**How it works:**
- The `OpenRouterProvider` now supports `CLAUDE_MEM_OPENROUTER_BASE_URL` environment variable
- If set, it overrides the default OpenRouter endpoint
- The provider automatically appends `/chat/completions` to the base URL
- All retry logic, error handling, and token tracking remain unchanged

### Option 2: Use Custom Relay Provider (Recommended for Production)

Use the new `CustomRelayProvider` for dedicated custom API support:

**Settings File (~/.claude-mem/settings.json):**
```json
{
  "CLAUDE_MEM_PROVIDER": "custom-relay",
  "CLAUDE_MEM_CUSTOM_RELAY_API_KEY": "your-api-key",
  "CLAUDE_MEM_CUSTOM_RELAY_MODEL": "gpt-3.5-turbo",
  "CLAUDE_MEM_CUSTOM_RELAY_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

**Environment Variables:**
```bash
export CLAUDE_MEM_PROVIDER="custom-relay"
export CLAUDE_MEM_CUSTOM_RELAY_API_KEY="your-api-key"
export CLAUDE_MEM_CUSTOM_RELAY_MODEL="gpt-3.5-turbo"
export CLAUDE_MEM_CUSTOM_RELAY_BASE_URL="http://127.0.0.1:4000/v1"
```

**Features:**
- Dedicated provider for custom OpenAI-compatible endpoints
- Full error classification and retry logic
- Token usage tracking
- Context window management
- Graceful degradation on network errors

## Setting Up Local Relay

### Using LiteLLM (Recommended)

1. **Install LiteLLM:**
```bash
pip install litellm
```

2. **Create config.yaml:**
```yaml
model_list:
  - model_name: mem-model
    litellm_params:
      model: openai/deepseek-chat
      api_key: "your-deepseek-api-key"
      api_base: "https://api.deepseek.com/v1"

router_settings:
  num_retries: 2
  timeout: 60
```

3. **Start LiteLLM proxy:**
```bash
litellm --config config.yaml --host 127.0.0.1 --port 4000
```

4. **Test the proxy:**
```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test" \
  -d '{
    "model": "mem-model",
    "messages": [{"role":"user","content":"hi"}]
  }'
```

### Using Custom Node.js Relay

Create `relay.js`:
```javascript
import express from "express";

const app = express();
app.use(express.json());

app.post("/v1/chat/completions", async (req, res) => {
  try {
    const response = await fetch("https://api.deepseek.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${process.env.DEEPSEEK_API_KEY}`
      },
      body: JSON.stringify(req.body)
    });

    const data = await response.json();
    res.status(response.status).json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(4000, () => {
  console.log("Relay running on http://127.0.0.1:4000");
});
```

Run it:
```bash
export DEEPSEEK_API_KEY="your-key"
node relay.js
```

## Configuration Reference

### OpenRouter with Custom Base URL

| Setting | Environment Variable | Default | Description |
|---------|----------------------|---------|-------------|
| Provider | `CLAUDE_MEM_PROVIDER` | `claude` | Set to `openrouter` |
| API Key | `CLAUDE_MEM_OPENROUTER_API_KEY` | - | Bearer token for relay |
| Model | `CLAUDE_MEM_OPENROUTER_MODEL` | `xiaomi/mimo-v2-flash:free` | Model name |
| Base URL | `CLAUDE_MEM_OPENROUTER_BASE_URL` | `https://openrouter.ai/api/v1` | Custom relay endpoint |
| Max Context | `CLAUDE_MEM_OPENROUTER_MAX_CONTEXT_MESSAGES` | `20` | Max messages in context |
| Max Tokens | `CLAUDE_MEM_OPENROUTER_MAX_TOKENS` | `100000` | Max estimated tokens |

### Custom Relay Provider

| Setting | Environment Variable | Default | Description |
|---------|----------------------|---------|-------------|
| Provider | `CLAUDE_MEM_PROVIDER` | `claude` | Set to `custom-relay` |
| API Key | `CLAUDE_MEM_CUSTOM_RELAY_API_KEY` | - | Bearer token for relay |
| Model | `CLAUDE_MEM_CUSTOM_RELAY_MODEL` | `gpt-3.5-turbo` | Model name |
| Base URL | `CLAUDE_MEM_CUSTOM_RELAY_BASE_URL` | - | Relay endpoint (required) |
| Max Context | `CLAUDE_MEM_CUSTOM_RELAY_MAX_CONTEXT_MESSAGES` | `20` | Max messages in context |
| Max Tokens | `CLAUDE_MEM_CUSTOM_RELAY_MAX_TOKENS` | `100000` | Max estimated tokens |

## Implementation Steps

### Step 1: Verify Third-Party API Works

```bash
curl https://api.deepseek.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key" \
  -d '{
    "model": "deepseek-chat",
    "messages": [{"role":"user","content":"test"}]
  }'
```

### Step 2: Deploy Local Relay

Choose LiteLLM or custom Node.js relay and start it on `127.0.0.1:4000`.

### Step 3: Verify Relay Works

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test" \
  -d '{
    "model": "mem-model",
    "messages": [{"role":"user","content":"test"}]
  }'
```

### Step 4: Configure claude-mem

Edit `~/.claude-mem/settings.json`:

**Option A (OpenRouter with custom base URL):**
```json
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "test",
  "CLAUDE_MEM_OPENROUTER_MODEL": "mem-model",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

**Option B (Custom Relay Provider):**
```json
{
  "CLAUDE_MEM_PROVIDER": "custom-relay",
  "CLAUDE_MEM_CUSTOM_RELAY_API_KEY": "test",
  "CLAUDE_MEM_CUSTOM_RELAY_MODEL": "mem-model",
  "CLAUDE_MEM_CUSTOM_RELAY_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

### Step 5: Test claude-mem

Start Claude Code and create a new session. Check logs:

```bash
npm run worker:logs
```

Look for:
- `Custom relay agent completed` (success)
- `Custom relay init failed` (error)

### Step 6: Monitor and Optimize

- Check token usage in logs
- Adjust `MAX_CONTEXT_MESSAGES` and `MAX_TOKENS` if needed
- Add fallback models in LiteLLM config for reliability

## Supported Models

### Recommended (OpenAI-compatible)

- **DeepSeek**: `deepseek-chat` (via api.deepseek.com)
- **Qwen**: `qwen-turbo` (via dashscope.aliyuncs.com)
- **Mistral**: `mistral-medium` (via api.mistral.ai)
- **Ollama**: Any local model (via localhost:11434)
- **Moonshot**: `moonshot-v1-8k` (via api.moonshot.cn)
- **Zhipu**: `glm-4` (via open.bigmodel.cn)

### Avoid (Proprietary)

- `openai/*` (use Claude instead)
- `google/*` (use Gemini provider)
- `anthropic/*` (use Claude provider)

## Error Handling

The custom relay provider classifies errors into:

| Error Type | Behavior | Example |
|-----------|----------|---------|
| `auth_invalid` | Blocking, requires fix | 401/403 status |
| `rate_limit` | Transient, retries with backoff | 429 status |
| `quota_exhausted` | Blocking, requires action | "quota exceeded" in response |
| `transient` | Retries with exponential backoff | 5xx status, network timeout |
| `unrecoverable` | Stops session | 400/404 status, malformed request |

## Troubleshooting

### "Custom relay API key not configured"

**Solution:** Set `CLAUDE_MEM_CUSTOM_RELAY_API_KEY` in settings or environment.

### "Custom relay base URL not configured"

**Solution:** Set `CLAUDE_MEM_CUSTOM_RELAY_BASE_URL` in settings or environment.

### "Custom relay network error"

**Solution:** 
- Verify relay is running: `curl http://127.0.0.1:4000/v1/chat/completions`
- Check firewall/proxy settings
- Verify base URL is correct (no trailing slash needed)

### "Custom relay upstream error (status 500)"

**Solution:**
- Check relay logs for upstream API errors
- Verify API key is correct
- Verify model name matches upstream provider

### "Custom relay rate limit (429)"

**Solution:**
- Reduce `MAX_CONTEXT_MESSAGES` to lower token usage
- Add retry logic in LiteLLM config
- Implement request queuing

## Advanced Configuration

### Multi-Model Fallback (LiteLLM)

```yaml
model_list:
  - model_name: mem-model
    litellm_params:
      model: openai/deepseek-chat
      api_key: "deepseek-key"
      api_base: "https://api.deepseek.com/v1"
  
  - model_name: mem-model-fallback
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: "openai-key"
      api_base: "https://api.openai.com/v1"

router_settings:
  num_retries: 2
  timeout: 60
  fallback_model: mem-model-fallback
```

### Request Logging (LiteLLM)

```yaml
router_settings:
  num_retries: 2
  timeout: 60
  log_requests: true
  log_responses: true
```

### Proxy Support

Set environment variables before starting relay:

```bash
export HTTP_PROXY="http://proxy.example.com:8080"
export HTTPS_PROXY="http://proxy.example.com:8080"
litellm --config config.yaml --host 127.0.0.1 --port 4000
```

## Summary

| Approach | Pros | Cons | Use Case |
|----------|------|------|----------|
| **OpenRouter + Custom Base URL** | Minimal changes, reuses existing logic | Limited to OpenRouter-compatible APIs | Quick testing, simple setups |
| **Custom Relay Provider** | Dedicated support, full error handling | Requires provider selection | Production deployments |
| **LiteLLM Proxy** | Multi-model support, fallback logic | Extra process to manage | Complex routing needs |
| **Custom Node.js Relay** | Full control, lightweight | Manual error handling | Simple single-model setups |

## Next Steps

1. Choose your relay approach (LiteLLM or custom)
2. Deploy and test the relay locally
3. Configure claude-mem with the relay endpoint
4. Monitor logs and adjust settings as needed
5. Consider adding fallback models for reliability
