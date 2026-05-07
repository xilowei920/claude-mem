# Claude-mem 外部代理（Relay）接入第三方模型实施方案（方案A）

---

## 一、目标

在不修改或最小修改 `claude-mem` 源码的前提下，实现：

```text
claude-mem → 本地代理（Relay） → 第三方模型 API
```

达到以下效果：

* 规避 OpenRouter / Gemini / OpenAI 区域限制
* 统一模型接口（OpenAI-compatible）
* 支持多模型 fallback
* 支持代理、重试、限流控制
* 后续更换模型无需改 claude-mem

---

## 二、总体架构

```text
claude-mem
  ↓
本地 Relay / LiteLLM / New API
  ↓
第三方模型 API（OpenAI-compatible）
  ↓
DeepSeek / 硅基流动 / 阿里百炼 / 火山方舟 / 智谱 / Moonshot / Ollama
```

核心思想：

```text
把所有模型统一包装成 OpenAI /v1/chat/completions 接口
```

---

## 三、推荐实现方案（LiteLLM Proxy）

### 1. 安装 LiteLLM

```bash
pip install litellm
```

---

### 2. 创建配置文件

创建 `config.yaml`：

```yaml
model_list:
  - model_name: mem-model
    litellm_params:
      model: openai/deepseek-chat
      api_key: "你的第三方API_KEY"
      api_base: "https://你的第三方OpenAI兼容地址/v1"

router_settings:
  num_retries: 2
  timeout: 60
```

---

### 3. 启动代理服务

```bash
litellm --config config.yaml --host 127.0.0.1 --port 4000
```

---

### 4. 测试代理是否正常

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

---

## 四、接入 claude-mem

---

### 方案1（优先）：支持自定义 baseURL

如果 claude-mem 支持：

```json
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_MODEL": "mem-model",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "test",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

---

### 方案2（推荐）：最小源码修改

修改 claude-mem 中 OpenRouter baseURL：

#### 原始代码：

```text
https://openrouter.ai/api/v1
```

#### 修改为：

```text
process.env.CLAUDE_MEM_OPENROUTER_BASE_URL || 默认值
```

---

#### 示例：

```js
const baseURL = process.env.CLAUDE_MEM_OPENROUTER_BASE_URL 
  || "https://openrouter.ai/api/v1";
```

---

然后配置：

```json
{
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

---

## 五、自定义 Relay（可选方案）

如果不使用 LiteLLM，可自建 Node 服务：

```js
import express from "express";

const app = express();
app.use(express.json());

app.post("/v1/chat/completions", async (req, res) => {
  const r = await fetch("https://你的上游API", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${process.env.API_KEY}`
    },
    body: JSON.stringify(req.body)
  });

  const text = await r.text();
  res.status(r.status).type("application/json").send(text);
});

app.listen(4000, () => {
  console.log("Relay running on http://127.0.0.1:4000");
});
```

---

## 六、推荐功能扩展

建议逐步加入：

```text
✔ 自动重试（429 / timeout）
✔ 多模型 fallback
✔ 日志记录
✔ 请求限流
✔ 代理支持
✔ 模型路由策略
```

---

## 七、推荐实施步骤

```text
1️⃣ 确认第三方模型 API 可用（curl 测试）
2️⃣ 部署 LiteLLM 或 Relay
3️⃣ 验证本地 /v1/chat/completions 接口
4️⃣ 修改 claude-mem baseURL 指向本地
5️⃣ 启动 claude，观察 observation 是否生成
6️⃣ 增加 fallback 和稳定性优化
```

---

## 八、模型选择建议

避免使用：

```text
❌ openai/*
❌ google/*
❌ anthropic/*
```

优先选择：

```text
✔ deepseek
✔ qwen
✔ mistral
✔ nvidia
✔ 国内 OpenAI-compatible 提供商
```

---

## 九、方案优势总结

```text
✔ 不修改 claude-mem 核心逻辑
✔ 支持任意模型接入
✔ 可统一处理代理/限流/错误
✔ 可扩展 fallback
✔ 长期可维护
```

---

## 十、实战经验：LiteLLM 的坑与自建代理方案

### 问题背景

使用 `capi.quan2go.com` 的 `gpt-5.4-mini` 模型时，LiteLLM 代理完全无法正常工作。

### LiteLLM 代理模式的致命限制

以下配置**全部无效**，无法阻止客户端 `stream:true` 透传给上游：

| 尝试的方案 | 结果 |
|-----------|------|
| `litellm_params.stream: false` | 仅作默认值，客户端请求覆盖 |
| `fake_stream: true` | 在 litellm_params 中不生效 |
| `model_info.supports_streaming: false` | 不影响代理行为 |
| `drop_params: true` | 不丢弃 stream 参数 |
| `async_pre_call_hook` 自定义回调 | 调用时机太晚 |
| 修补 `proxy_server.py` 入口 | 被 `openai.py` 硬编码 `data["stream"]=True` 覆盖 |

**根本原因**：LiteLLM 的 `openai.py` 中 `streaming()` 和 `async_streaming()` 方法硬编码 `data["stream"] = True`（第1012/1084行），覆盖所有上游设置。

### 上游 API 的非标准行为

`capi.quan2go.com` 的 `gpt-5.4-mini` 有以下非标准行为：

```text
1. 始终返回 SSE 流式格式，完全忽略 stream:false
2. stream:false 时内容丢失，只返回空 delta 结束 chunk
3. delta 中包含非标准 reasoning 字段（思考链）
4. 大部分 chunk 的 content 为空字符串，reasoning 完成后 content 才有值
```

### 最终方案：自建 Python 代理（proxy_bridge.py）

直接替代 LiteLLM，用 aiohttp 实现：

```python
"""
proxy_bridge.py - 放在 ~/litellm/ 目录
启动: cd ~/litellm && source ~/litellm-env/bin/activate && python proxy_bridge.py
"""
import json, time, uuid, asyncio
from aiohttp import web, ClientSession

UPSTREAM_URL = "https://capi.quan2go.com/v1/chat/completions"
API_KEY = "你的API_KEY"
PORT = 4000
MAX_CONCURRENT = 3
semaphore = asyncio.Semaphore(MAX_CONCURRENT)

async def collect_sse_chunks(upstream_resp):
    content_parts, reasoning_parts = [], []
    model, resp_id = "gpt-5.4-mini", None
    buffer = ""
    async for chunk in upstream_resp.content:
        buffer += chunk.decode("utf-8", errors="replace")
        while "\n" in buffer:
            line, buffer = buffer.split("\n", 1)
            line = line.strip()
            if not line or not line.startswith("data: "): continue
            data_str = line[6:]
            if data_str == "[DONE]": break
            try:
                data = json.loads(data_str)
                resp_id = resp_id or data.get("id")
                model = data.get("model", model)
                choices = data.get("choices", [])
                if choices:
                    delta = choices[0].get("delta", {})
                    if delta.get("content"): content_parts.append(delta["content"])
                    if delta.get("reasoning"): reasoning_parts.append(delta["reasoning"])
            except json.JSONDecodeError: pass
    content = "".join(content_parts) or "".join(reasoning_parts)
    return {
        "id": resp_id or f"chatcmpl-{uuid.uuid4()}",
        "object": "chat.completion", "created": int(time.time()), "model": model,
        "choices": [{"index":0,"message":{"role":"assistant","content":content},"finish_reason":"stop"}],
        "usage": {"prompt_tokens":0,"completion_tokens":0,"total_tokens":0}
    }

async def handle_chat_completions(request):
    async with semaphore:
        body = await request.json()
        body["stream"] = True  # 上游只在流式模式才返回内容
        headers = {"Content-Type":"application/json","Authorization":f"Bearer {API_KEY}"}
        async with ClientSession() as session:
            async with session.post(UPSTREAM_URL, json=body, headers=headers) as resp:
                if resp.status != 200:
                    return web.json_response({"error":{"message":await resp.text()}}, status=resp.status)
                return web.json_response(await collect_sse_chunks(resp))

app = web.Application()
app.router.add_post("/v1/chat/completions", handle_chat_completions)
app.router.add_post("/chat/completions", handle_chat_completions)

if __name__ == "__main__":
    web.run_app(app, host="0.0.0.0", port=PORT)
```

工作原理：

```text
1. 接收客户端请求（无论 stream 值）
2. 强制 stream:true 调上游（上游只有流式才返回内容）
3. 收集所有 SSE chunks，合并 content + reasoning 字段
4. 返回标准 OpenAI 非流式 JSON 响应
5. 信号量限制并发数（防止上游 429）
```

### 经验总结

```text
✔ LiteLLM 适合标准 OpenAI 兼容 API，非标准 API 建议自建代理
✔ 上游 API 可能不遵守 stream 参数 — 必须用 curl 验证实际行为
✔ 非标准字段（如 reasoning）需要在代理层处理
✔ 自建代理更轻量、可控，无 LiteLLM 的层层覆盖问题
```

---

## 十一、最终实施方案（2026-05-06 验证完成）

### 架构确认

```text
claude-mem worker (port 37778)
  ↓ [OpenRouterProvider.ts]
proxy_bridge.py (port 4000, WSL Ubuntu-24.04)
  ↓ [SSE → non-streaming 转换]
capi.quan2go.com/v1/chat/completions
  ↓ [gpt-5.4-mini 模型]
响应 → 存储 → 内存压缩 → 上下文注入
```

### proxy_bridge.py 最终版本

**位置**: `\\wsl.localhost\Ubuntu-24.04\home\laserqc\litellm\proxy_bridge.py`

**关键特性**:
- ✅ 环境变量配置（`UPSTREAM_API_KEY`, `PROXY_TOKEN`, `PROXY_HOST`, `PROXY_PORT`）
- ✅ 入站认证（可选 Bearer token）
- ✅ 自动重试（指数退避，MAX_RETRIES=2）
- ✅ 请求限流（RPM_LIMIT=10）
- ✅ 超时控制（TIMEOUT_SECONDS=60）
- ✅ 并发限制（MAX_CONCURRENT=3）
- ✅ SSE chunk 收集与合并
- ✅ 非标准字段处理（reasoning 字段）
- ✅ Token 估算（无 usage 时）
- ✅ `/health` 端点

**启动命令**:
```bash
cd /home/laserqc/litellm && \
UPSTREAM_API_KEY='CC6368A4-BB47-4AB4-B18B-41EF5963B985' \
nohup python3 proxy_bridge.py > /tmp/proxy_bridge.log 2>&1 &
```

### OpenRouterProvider.ts 修改

**文件**: `src/services/worker/OpenRouterProvider.ts`

**修改内容**:
1. 添加 URL 验证（防止无效 baseURL）
2. 移出重试循环外（避免重复解析）
3. 支持自定义 baseURL（`CLAUDE_MEM_OPENROUTER_BASE_URL`）

**关键代码**:
```typescript
function getOpenRouterApiUrl(): string {
  const settings = SettingsDefaultsManager.loadFromFile(USER_SETTINGS_PATH);
  const customBaseUrl = settings.CLAUDE_MEM_OPENROUTER_BASE_URL;
  if (customBaseUrl) {
    try { new URL(customBaseUrl); } catch {
      logger.error('SDK', `Invalid OPENROUTER_BASE_URL: ${customBaseUrl}, falling back to default`);
      return DEFAULT_OPENROUTER_API_URL;
    }
    const baseUrl = customBaseUrl.replace(/\/+$/, '');
    return `${baseUrl}/chat/completions`;
  }
  return DEFAULT_OPENROUTER_API_URL;
}
```

### settings.json 配置

```json
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_MODEL": "gpt-5.4-mini",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "test",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "http://127.0.0.1:4000/v1"
}
```

---

## 十二、每日启动流程

### 方式1：手动启动（推荐）

**步骤1：启动 proxy_bridge**
```powershell
wsl -d Ubuntu-24.04 -- bash -c "cd /home/laserqc/litellm && UPSTREAM_API_KEY='CC6368A4-BB47-4AB4-B18B-41EF5963B985' nohup python3 proxy_bridge.py > /tmp/proxy_bridge.log 2>&1 &"
```

**步骤2：验证 proxy_bridge**
```powershell
curl.exe -s http://127.0.0.1:4000/health | ConvertFrom-Json
```

**步骤3：启动 claude-mem worker**
```powershell
cd D:\GitHub\claude-mem
npm run build-and-sync
npm run worker:restart
```

**步骤4：验证 worker**
```powershell
curl.exe -s http://127.0.0.1:37778/health
```

### 方式2：自动化脚本（备选）

**脚本位置**: `scripts/start-relay-chain.ps1`

**用法**:
```powershell
# 完整启动（proxy_bridge + worker）
.\scripts\start-relay-chain.ps1

# 仅启动 worker（proxy_bridge 已在运行）
.\scripts\start-relay-chain.ps1 -SkipProxy

# 详细日志
.\scripts\start-relay-chain.ps1 -Verbose
```

**脚本功能**:
- ✅ 自动杀死旧进程
- ✅ 启动 proxy_bridge（WSL）
- ✅ 等待端口就绪
- ✅ 健康检查
- ✅ 启动 claude-mem worker
- ✅ 验证端点可用

---

## 十三、验证办法

### 1. 代理层验证

**健康检查**:
```powershell
curl.exe -s http://127.0.0.1:4000/health | ConvertFrom-Json
```

**预期输出**:
```json
{
  "status": "ok",
  "upstream": "https://capi.quan2go.com/v1/chat/completions",
  "config": {
    "max_concurrent": 3,
    "max_retries": 2,
    "timeout_seconds": 60,
    "rpm_limit": 10
  }
}
```

**测试请求**:
```powershell
$body = @{
  model = "gpt-5.4-mini"
  messages = @(@{role = "user"; content = "hello"})
} | ConvertTo-Json

curl.exe -X POST http://127.0.0.1:4000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer test" `
  -d $body
```

**预期**:
- 返回 200 OK
- 包含 `choices[0].message.content` 字段
- 包含 `usage` 字段

### 2. Worker 层验证

**健康检查**:
```powershell
curl.exe -s http://127.0.0.1:37778/health
```

**查看日志**:
```powershell
npm run worker:logs
```

**预期**:
- 无 ERROR 级别日志
- 包含 `OpenRouter initialized` 消息
- 包含 `proxy_bridge` 相关请求日志

### 3. 端到端验证

**打开 Web UI**:
```
http://localhost:37777
```

**操作**:
1. 在 Claude Code 中提交任何代码问题
2. 观察 Web UI 中是否出现新的 DISCOVERY 卡片
3. 检查卡片中是否包含观察数据

**预期**:
- 新卡片在 5-10 秒内出现
- 卡片包含 `hasSummary: true`
- 无错误消息

### 4. 日志检查

**proxy_bridge 日志**:
```bash
wsl -d Ubuntu-24.04 -- tail -f /tmp/proxy_bridge.log
```

**预期**:
```
[HH:MM:SS] [RATE] Throttling X.Xs (RPM=10)  # 正常限流
[HH:MM:SS] [RETRY] 429 rate limited, waiting Xs  # 正常重试
```

**worker 日志**:
```powershell
npm run worker:logs | Select-String "ERROR|WARN" -Context 2
```

**预期**:
- 无 ERROR 日志
- 可能有 WARN（正常）

---

## 十四、故障排查

### 问题1：proxy_bridge 无法启动

**症状**: `pgrep -f proxy_bridge` 返回空

**排查**:
```bash
wsl -d Ubuntu-24.04 -- bash -c "cd /home/laserqc/litellm && python3 proxy_bridge.py"
```

**常见原因**:
- aiohttp 未安装：`pip3 install --break-system-packages aiohttp`
- Python 版本过低：需要 3.8+
- 端口被占用：`ss -tlnp | grep 4000`

### 问题2：proxy_bridge 返回 401

**症状**: `curl` 返回 `{"error": "unauthorized"}`

**原因**: 缺少 `Authorization: Bearer test` 头

**解决**:
```powershell
curl.exe -H "Authorization: Bearer test" http://127.0.0.1:4000/health
```

### 问题3：proxy_bridge 返回 502

**症状**: `{"error": {"message": "Failed after 2 attempts", "type": "proxy_error", "code": 502}}`

**排查**:
```bash
wsl -d Ubuntu-24.04 -- tail -20 /tmp/proxy_bridge.log
```

**常见原因**:
- 上游 API 不可达：检查网络和 VPN
- API_KEY 错误：验证 `UPSTREAM_API_KEY` 环境变量
- 上游返回 429：等待后重试

### 问题4：worker 无法连接 proxy_bridge

**症状**: worker 日志中出现 `ECONNREFUSED 127.0.0.1:4000`

**排查**:
```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 4000
```

**解决**:
1. 确认 proxy_bridge 在运行：`wsl -d Ubuntu-24.04 -- pgrep -f proxy_bridge`
2. 确认 WSL 网络可达：`wsl -d Ubuntu-24.04 -- curl http://127.0.0.1:4000/health`
3. 重启 WSL：`wsl --shutdown`

---

## 十五、调优记录（2026-05-06）

### 问题5：观察解析失败（空内容）

**症状**:
```
[ERROR] [PARSER] Observation missing type field, using "bugfix"
[WARN ] [PARSER] Skipping empty observation (all content fields null)
[WARN ] [PARSER] OpenRouter returned unparseable response — leaving queue intact
```

**根因**: `CLAUDE_MEM_OPENROUTER_MAX_TOKENS=4096` 控制的是上下文窗口截断阈值。init prompt 本身约 4000 tokens，导致对话被截断到只剩 2 条消息，模型缺乏上下文无法生成有意义的观察。

**日志证据**:
```
Context window truncated to prevent runaway costs {originalMessages=23, keptMessages=2, droppedMessages=21, estimatedTokens=4084, tokenLimit=4096}
```

**修复**:
```json
{
  "CLAUDE_MEM_OPENROUTER_MAX_CONTEXT_MESSAGES": "6",
  "CLAUDE_MEM_OPENROUTER_MAX_TOKENS": "16384"
}
```

- `MAX_TOKENS`: 4096 → 16384（给 init prompt 足够空间）
- `MAX_CONTEXT_MESSAGES`: 20 → 6（减少发送的对话轮数，避免触发 Cloudflare 超时）

---

### 问题6：API Error 524

**症状**: proxy_bridge 返回 524 错误

**根因**: Cloudflare 网关超时（100s）。调大 MAX_TOKENS 后上下文变大，upstream 处理时间超过 Cloudflare 限制。

**修复**: 配合减少 `MAX_CONTEXT_MESSAGES` 到 6，每次请求 token 量控制在 8000-12000，远低于超时阈值。

---

### 问题7：偶发空响应

**症状**:
```
[ERROR] [SDK] Empty response from OpenRouter
[ERROR] [SDK] Empty OpenRouter init response - session may lack context
```

**根因**: upstream 偶尔返回空 content（SSE 流中无有效 delta）。

**修复**: proxy_bridge.py 增加空内容重试逻辑：

```python
result = await collect_sse_chunks(resp)
content = result.get("choices", [{}])[0].get("message", {}).get("content", "")
if not content and attempt < MAX_RETRIES:
    delay = 2 ** attempt
    print(f"[RETRY] Empty content from upstream, waiting {delay}s")
    await asyncio.sleep(delay)
    last_error = "Empty content"
    continue
return web.json_response(result)
```

收到空内容时自动重试（最多 MAX_RETRIES 次），而非直接返回空响应给 worker。

---

### 最终配置参数

| 参数 | 旧值 | 新值 | 原因 |
|------|------|------|------|
| `CLAUDE_MEM_OPENROUTER_MAX_TOKENS` | 4096 | 16384 | 避免 init prompt 被截断 |
| `CLAUDE_MEM_OPENROUTER_MAX_CONTEXT_MESSAGES` | 20 | 6 | 避免 Cloudflare 524 超时 |
| proxy_bridge 空内容重试 | 无 | 有 | 应对 upstream 偶发空响应 |

---

### 问题8：pending_messages 表缺少 retry_count 列（2026-05-07）

**症状**:
```
[ERROR] [SESSION] Failed to persist observation to DB table pending_messages has no column named retry_count
```

**根因**: 数据库迁移 v31/v32 已删除 `retry_count` 列，但部署的 `worker-service.cjs` bundle 是旧版本，INSERT 语句仍引用该列。

**修复**: 重新执行 `npm run build` 生成新 bundle，部署到 plugin cache 目录。

---

### 问题9：空响应不触发重试（2026-05-07）

**症状**: 模型偶尔返回空 content，worker 直接返回 `{ content: '' }` 不重试。

**根因**: `OpenRouterProvider.ts` 中空内容检查在 `withRetry` 回调外部，不会触发重试机制。

**修复** (`src/services/worker/OpenRouterProvider.ts:503-508`):
```typescript
if (!responseData.choices?.[0]?.message?.content) {
  throw new ClassifiedProviderError(
    'OpenRouter returned empty content',
    { kind: 'transient', cause: new Error('Empty content in 200 response') },
  );
}
```

将空内容检查移入 `withRetry` 回调内部，抛出 `transient` 类型错误，自动重试最多 2 次。

---

### 问题10：模型返回非标准 observation type（2026-05-07）

**症状**:
```
[ERROR] [PARSER] Invalid observation type: write, using "bugfix"
[ERROR] [PARSER] Invalid observation type: verification, using "bugfix"
```

**根因**: gpt-5.4-mini 不严格遵循 XML prompt 中定义的 type 枚举，返回 `write`、`verification` 等自由文本。

**修复** (`src/sdk/parser.ts:5-12`):
```typescript
const TYPE_ALIASES: Record<string, string> = {
  write: 'change', edit: 'change', update: 'change', modify: 'change',
  fix: 'bugfix', patch: 'bugfix', repair: 'bugfix',
  add: 'feature', create: 'feature', implement: 'feature', new: 'feature',
  find: 'discovery', explore: 'discovery', investigate: 'discovery',
  verification: 'discovery', check: 'discovery', test: 'discovery', debug: 'discovery',
  restructure: 'refactor', cleanup: 'refactor', reorganize: 'refactor',
};
```

模块级别名映射表，将非标准 type 自动转换为有效类型。

---

## 十六、一句话总结

> **通过 proxy_bridge.py 将 claude-mem 与第三方模型解耦，实现稳定、可控的模型调用体系。每日启动一条命令，自动化脚本处理所有细节。**

---
