# Integration Checklist for Custom Relay Provider

## Overview

This checklist guides you through integrating the `CustomRelayProvider` into claude-mem's worker service. The implementation is complete and ready to use.

## Files Created

✅ **src/services/worker/CustomRelayProvider.ts** (500+ lines)
- Complete custom relay provider implementation
- Error classification and retry logic
- Token tracking and context management
- Full feature parity with OpenRouterProvider

✅ **CUSTOM_RELAY_INTEGRATION.md**
- Comprehensive setup guide
- LiteLLM and custom relay examples
- Configuration reference
- Troubleshooting guide

✅ **IMPLEMENTATION_SUMMARY.md**
- Overview of changes
- Quick start guide
- Architecture diagram
- Supported models

## Files Modified

✅ **src/services/worker/OpenRouterProvider.ts**
- Added `getOpenRouterApiUrl()` function
- Supports `CLAUDE_MEM_OPENROUTER_BASE_URL` environment variable
- Maintains backward compatibility

## Integration Steps

### Step 1: Export CustomRelayProvider

Add to `src/services/worker/index.ts` (or create if needed):

```typescript
export { CustomRelayProvider, isCustomRelayAvailable, isCustomRelaySelected, classifyCustomRelayError } from './CustomRelayProvider.js';
```

### Step 2: Update Worker Service Provider Selection

In `src/services/worker-service.ts`, add CustomRelayProvider to the provider selection logic:

```typescript
import { CustomRelayProvider, isCustomRelayAvailable, isCustomRelaySelected } from './worker/CustomRelayProvider.js';

// In the provider selection section:
if (isCustomRelaySelected() && isCustomRelayAvailable()) {
  const provider = new CustomRelayProvider(dbManager, sessionManager);
  await provider.startSession(session, worker);
} else if (isOpenRouterSelected() && isOpenRouterAvailable()) {
  const provider = new OpenRouterProvider(dbManager, sessionManager);
  await provider.startSession(session, worker);
} else if (isGeminiSelected() && isGeminiAvailable()) {
  const provider = new GeminiProvider(dbManager, sessionManager);
  await provider.startSession(session, worker);
} else if (isClaudeAvailable()) {
  const provider = new ClaudeProvider(dbManager, sessionManager);
  await provider.startSession(session, worker);
}
```

### Step 3: Add Tests (Optional but Recommended)

Create `tests/services/worker/CustomRelayProvider.test.ts`:

```typescript
import { describe, it, expect, beforeEach, mock } from 'bun:test';
import { CustomRelayProvider, classifyCustomRelayError } from '../../../src/services/worker/CustomRelayProvider.js';
import { ClassifiedProviderError } from '../../../src/services/worker/provider-errors.js';

describe('CustomRelayProvider', () => {
  describe('classifyCustomRelayError', () => {
    it('should classify 401 as auth_invalid', () => {
      const error = classifyCustomRelayError({
        status: 401,
        bodyText: 'Unauthorized',
        cause: new Error('401 Unauthorized')
      });
      expect(error.kind).toBe('auth_invalid');
    });

    it('should classify 429 as rate_limit', () => {
      const error = classifyCustomRelayError({
        status: 429,
        bodyText: 'Too Many Requests',
        cause: new Error('429 Too Many Requests')
      });
      expect(error.kind).toBe('rate_limit');
    });

    it('should classify quota exceeded as quota_exhausted', () => {
      const error = classifyCustomRelayError({
        status: 400,
        bodyText: 'quota exceeded',
        cause: new Error('Quota exceeded')
      });
      expect(error.kind).toBe('quota_exhausted');
    });

    it('should classify 5xx as transient', () => {
      const error = classifyCustomRelayError({
        status: 500,
        bodyText: 'Internal Server Error',
        cause: new Error('500 Internal Server Error')
      });
      expect(error.kind).toBe('transient');
    });

    it('should classify network errors as transient', () => {
      const error = classifyCustomRelayError({
        cause: new Error('ECONNREFUSED')
      });
      expect(error.kind).toBe('transient');
    });
  });
});
```

### Step 4: Build and Test

```bash
# Build the project
npm run build

# Run tests
npm test

# Build and sync to marketplace
npm run build-and-sync

# Check worker logs
npm run worker:logs
```

### Step 5: Verify TypeScript Compilation

```bash
npm run typecheck
```

## Configuration Examples

### Quick Test (OpenRouter with Custom Base URL)

```bash
# Set environment variables
export CLAUDE_MEM_PROVIDER="openrouter"
export CLAUDE_MEM_OPENROUTER_API_KEY="test"
export CLAUDE_MEM_OPENROUTER_MODEL="mem-model"
export CLAUDE_MEM_OPENROUTER_BASE_URL="http://127.0.0.1:4000/v1"

# Or edit ~/.claude-mem/settings.json
cat > ~/.claude-mem/settings.json << 'EOF'
{
  "CLAUDE_MEM_PROVIDER": "openrouter",
  "CLAUDE_MEM_OPENROUTER_API_KEY": "test",
  "CLAUDE_MEM_OPENROUTER_MODEL": "mem-model",
  "CLAUDE_MEM_OPENROUTER_BASE_URL": "http://127.0.0.1:4000/v1"
}
EOF
```

### Production Setup (Custom Relay Provider)

```bash
cat > ~/.claude-mem/settings.json << 'EOF'
{
  "CLAUDE_MEM_PROVIDER": "custom-relay",
  "CLAUDE_MEM_CUSTOM_RELAY_API_KEY": "your-api-key",
  "CLAUDE_MEM_CUSTOM_RELAY_MODEL": "deepseek-chat",
  "CLAUDE_MEM_CUSTOM_RELAY_BASE_URL": "http://127.0.0.1:4000/v1",
  "CLAUDE_MEM_CUSTOM_RELAY_MAX_CONTEXT_MESSAGES": "20",
  "CLAUDE_MEM_CUSTOM_RELAY_MAX_TOKENS": "100000"
}
EOF
```

## Deployment Checklist

- [ ] CustomRelayProvider.ts created and compiles
- [ ] OpenRouterProvider.ts modified with custom base URL support
- [ ] Provider selection logic updated in worker-service.ts
- [ ] Tests created and passing
- [ ] TypeScript compilation successful (`npm run typecheck`)
- [ ] Build successful (`npm run build`)
- [ ] Worker service restarts without errors
- [ ] Settings file configured with relay endpoint
- [ ] Local relay (LiteLLM or custom) running on 127.0.0.1:4000
- [ ] Test session created and observations generated
- [ ] Worker logs show "Custom relay agent completed"

## Troubleshooting

### "Cannot find module 'CustomRelayProvider'"

**Solution:** Ensure the export is added to `src/services/worker/index.ts` and the import path is correct.

### "CLAUDE_MEM_PROVIDER is not recognized"

**Solution:** Ensure the provider selection logic is updated in `worker-service.ts` to check for `custom-relay`.

### "Custom relay API key not configured"

**Solution:** Set `CLAUDE_MEM_CUSTOM_RELAY_API_KEY` in settings or environment variable.

### TypeScript compilation errors

**Solution:** Run `npm run typecheck` to identify issues. Common issues:
- Missing imports
- Type mismatches in provider interface
- Incorrect function signatures

## Next Steps

1. **Integrate CustomRelayProvider into worker-service.ts**
   - Add provider selection logic
   - Test with environment variables

2. **Create tests**
   - Error classification tests
   - Integration tests with mock relay

3. **Update documentation**
   - Add CustomRelayProvider to CLAUDE.md
   - Add examples to README.md

4. **Deploy and monitor**
   - Test with LiteLLM relay
   - Monitor logs for errors
   - Adjust settings as needed

## Support

For issues or questions:
1. Check `CUSTOM_RELAY_INTEGRATION.md` for setup help
2. Review `IMPLEMENTATION_SUMMARY.md` for architecture overview
3. Check worker logs: `npm run worker:logs`
4. Verify relay is running: `curl http://127.0.0.1:4000/v1/chat/completions`

## Summary

The custom relay implementation is complete and ready to integrate. Two approaches are available:

1. **Quick approach**: Use OpenRouter provider with custom base URL (minimal changes)
2. **Production approach**: Use CustomRelayProvider (full features)

Both support any OpenAI-compatible endpoint and maintain claude-mem's core architecture.
