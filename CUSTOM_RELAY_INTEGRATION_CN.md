# Claude-Mem 自定义 API 中继集成指南

## 概述

本指南说明如何将 claude-mem 与自定义 OpenAI 兼容的 API 端点（如 LiteLLM、本地代理或第三方模型提供商）集成，无需修改 claude-mem 源代码。

## 架构

```
claude-mem
  ↓
本地中继 / LiteLLM / 自定义代理
  ↓
第三方模型 API（OpenAI 兼容）
  ↓
DeepSeek / Qwen / Mistral / Ollama / 等
```

## 实现选项

### 选项 1：使用 OpenRouter + 自定义 Base URL（最小改动）

修改 OpenRouter 提供商以指向本地中继：

**环境变量：**
```bash
export CLAUDE_MEM_OPENROUTER_BASE_URL="http://127.0.0.1:4000/v1"
```

**设置文件 (~/.claude-mem/settings.json)：**
```json
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "test-key",
  "CLAUDE_MEM_OPENROUTER_MODEL": "mem-model",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

**工作原理：**
- `OpenRouterProvider` 现在支持 `CLAUDE_MEM_OPENROUTER_BASE_URL` 环境变量
- 如果设置，它会覆盖默认的 OpenRouter 端点
- 提供商自动将 `/chat/completions` 附加到 base URL
- 所有重试逻辑、错误处理和 token 追踪保持不变

### 选项 2：使用自定义中继提供商（推荐用于生产）

使用新的 `CustomRelayProvider` 以获得专门的自定义 API 支持：

**设置文件 (~/.claude-mem/settings.json)：**
```json
{
  "CLAUDE_MEM_PROVIDER": "custom-relay",
  "CLAUDE_MEM_CUSTOM_RELAY_API_KEY": "your-api-key",
  "CLAUDE_MEM_CUSTOM_RELAY_MODEL": "gpt-3.5-turbo",
  "CLAUDE_MEM_CUSTOM_RELAY_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

**环境变量：**
```bash
export CLAUDE_MEM_PROVIDER="custom-relay"
export CLAUDE_MEM_CUSTOM_RELAY_API_KEY="your-api-key"
export CLAUDE_MEM_CUSTOM_RELAY_MODEL="gpt-3.5-turbo"
export CLAUDE_MEM_CUSTOM_RELAY_BASE_URL="http://127.0.0.1:4000/v1"
```

**功能特性：**
- 专门用于自定义 OpenAI 兼容端点的提供商
- 完整的错误分类和重试逻辑
- Token 使用追踪
- 上下文窗口管理
- 网络错误优雅降级

## 设置本地中继

### 使用 LiteLLM（推荐）

1. **安装 LiteLLM：**
```bash
pip install litellm
```

2. **创建配置文件 config.yaml：**
```yaml
model_list:
  - model_name: mem-model
    litellm_params:
      model: openai/deepseek-chat
      api_key: "你的-deepseek-api-key"
      api_base: "https://api.deepseek.com/v1"

router_settings:
  num_retries: 2
  timeout: 60
```

3. **启动代理服务：**
```bash
litellm --config config.yaml --host 127.0.0.1 --port 4000
```

4. **测试代理是否正常：**
```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test" \
  -d '{
    "model": "mem-model",
    "messages": [{"role":"user","content":"hi"}]
  }'
```

成功标志：
```text
返回 JSON 且包含 choices 字段
```

### 使用自定义 Node.js 中继

创建 `relay.js`：
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
  console.log("中继运行在 http://127.0.0.1:4000");
});
```

运行它：
```bash
export DEEPSEEK_API_KEY="your-key"
node relay.js
```

## 配置参考

### OpenRouter + 自定义 Base URL

| 设置 | 环境变量 | 默认值 | 说明 |
|------|---------|--------|------|
| 提供商 | `CLAUDE_MEM_PROVIDER` | `claude` | 设置为 `openrouter` |
| API 密钥 | `CLAUDE_MEM_OPENROUTER_API_KEY` | - | 中继的 Bearer 令牌 |
| 模型 | `CLAUDE_MEM_OPENROUTER_MODEL` | `xiaomi/mimo-v2-flash:free` | 模型名称 |
| Base URL | `CLAUDE_MEM_OPENROUTER_BASE_URL` | `https://openrouter.ai/api/v1` | 自定义中继端点 |
| 最大上下文 | `CLAUDE_MEM_OPENROUTER_MAX_CONTEXT_MESSAGES` | `20` | 上下文中的最大消息数 |
| 最大 Token | `CLAUDE_MEM_OPENROUTER_MAX_TOKENS` | `100000` | 最大估计 token 数 |

### 自定义中继提供商

| 设置 | 环境变量 | 默认值 | 说明 |
|------|---------|--------|------|
| 提供商 | `CLAUDE_MEM_PROVIDER` | `claude` | 设置为 `custom-relay` |
| API 密钥 | `CLAUDE_MEM_CUSTOM_RELAY_API_KEY` | - | 中继的 Bearer 令牌 |
| 模型 | `CLAUDE_MEM_CUSTOM_RELAY_MODEL` | `gpt-3.5-turbo` | 模型名称 |
| Base URL | `CLAUDE_MEM_CUSTOM_RELAY_BASE_URL` | - | 中继端点（必需） |
| 最大上下文 | `CLAUDE_MEM_CUSTOM_RELAY_MAX_CONTEXT_MESSAGES` | `20` | 上下文中的最大消息数 |
| 最大 Token | `CLAUDE_MEM_CUSTOM_RELAY_MAX_TOKENS` | `100000` | 最大估计 token 数 |

## 实施步骤

### 第 1 步：验证第三方 API 可用

```bash
curl https://api.deepseek.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key" \
  -d '{
    "model": "deepseek-chat",
    "messages": [{"role":"user","content":"test"}]
  }'
```

### 第 2 步：部署本地中继

选择 LiteLLM 或自定义 Node.js 中继，并在 `127.0.0.1:4000` 上启动它。

### 第 3 步：验证中继工作

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test" \
  -d '{
    "model": "mem-model",
    "messages": [{"role":"user","content":"test"}]
  }'
```

### 第 4 步：配置 claude-mem

编辑 `~/.claude-mem/settings.json`：

**选项 A（OpenRouter + 自定义 base URL）：**
```json
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "test",
  "CLAUDE_MEM_OPENROUTER_MODEL": "mem-model",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

**选项 B（自定义中继提供商）：**
```json
{
  "CLAUDE_MEM_PROVIDER": "custom-relay",
  "CLAUDE_MEM_CUSTOM_RELAY_API_KEY": "test",
  "CLAUDE_MEM_CUSTOM_RELAY_MODEL": "mem-model",
  "CLAUDE_MEM_CUSTOM_RELAY_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

### 第 5 步：测试 claude-mem

启动 Claude Code 并创建新会话。检查日志：

```bash
npm run worker:logs
```

查找：
- `Custom relay agent completed`（成功）
- `Custom relay init failed`（错误）

### 第 6 步：监控和优化

- 检查日志中的 token 使用情况
- 如果需要，调整 `MAX_CONTEXT_MESSAGES` 和 `MAX_TOKENS`
- 在 LiteLLM 配置中添加备用模型以提高可靠性

## 支持的模型

### 推荐（OpenAI 兼容）

- **DeepSeek**: `deepseek-chat`（通过 api.deepseek.com）
- **Qwen**: `qwen-turbo`（通过 dashscope.aliyuncs.com）
- **Mistral**: `mistral-medium`（通过 api.mistral.ai）
- **Ollama**: 任何本地模型（通过 localhost:11434）
- **Moonshot**: `moonshot-v1-8k`（通过 api.moonshot.cn）
- **智谱**: `glm-4`（通过 open.bigmodel.cn）

### 避免（专有）

- `openai/*`（改用 Claude）
- `google/*`（改用 Gemini 提供商）
- `anthropic/*`（改用 Claude 提供商）

## 错误处理

自定义中继提供商将错误分类为：

| 错误类型 | 行为 | 示例 |
|---------|------|------|
| `auth_invalid` | 阻止，需要修复 | 401/403 状态 |
| `rate_limit` | 临时，使用退避重试 | 429 状态 |
| `quota_exhausted` | 阻止，需要操作 | 响应中的"配额已超" |
| `transient` | 使用指数退避重试 | 5xx 状态、网络超时 |
| `unrecoverable` | 停止会话 | 400/404 状态、格式错误的请求 |

## 故障排除

### "自定义中继 API 密钥未配置"

**解决方案：** 在设置或环境中设置 `CLAUDE_MEM_CUSTOM_RELAY_API_KEY`。

### "自定义中继 base URL 未配置"

**解决方案：** 在设置或环境中设置 `CLAUDE_MEM_CUSTOM_RELAY_BASE_URL`。

### "自定义中继网络错误"

**解决方案：**
- 验证中继正在运行：`curl http://127.0.0.1:4000/v1/chat/completions`
- 检查防火墙/代理设置
- 验证 base URL 正确（不需要尾部斜杠）

### "自定义中继上游错误（状态 500）"

**解决方案：**
- 检查中继日志中的上游 API 错误
- 验证 API 密钥正确
- 验证模型名称与上游提供商匹配

### "自定义中继限流（429）"

**解决方案：**
- 减少 `MAX_CONTEXT_MESSAGES` 以降低 token 使用
- 在 LiteLLM 配置中添加重试逻辑
- 实现请求队列

## 高级配置

### 多模型备用（LiteLLM）

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

### 请求日志（LiteLLM）

```yaml
router_settings:
  num_retries: 2
  timeout: 60
  log_requests: true
  log_responses: true
```

### 代理支持

在启动中继前设置环境变量：

```bash
export HTTP_PROXY="http://proxy.example.com:8080"
export HTTPS_PROXY="http://proxy.example.com:8080"
litellm --config config.yaml --host 127.0.0.1 --port 4000
```

## 总结

| 方案 | 优点 | 缺点 | 用途 |
|------|------|------|------|
| **OpenRouter + 自定义 Base URL** | 最小改动，重用现有逻辑 | 仅限于 OpenRouter 兼容的 API | 快速测试、简单设置 |
| **自定义中继提供商** | 专门支持、完整错误处理 | 需要提供商选择 | 生产部署 |
| **LiteLLM 代理** | 多模型支持、备用逻辑 | 需要管理额外进程 | 复杂路由需求 |
| **自定义 Node.js 中继** | 完全控制、轻量级 | 手动错误处理 | 简单单模型设置 |

## 后续步骤

1. 选择中继方案（LiteLLM 或自定义）
2. 在本地部署并测试中继
3. 使用中继端点配置 claude-mem
4. 监控日志并根据需要调整设置
5. 考虑添加备用模型以提高可靠性
