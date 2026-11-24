# Flutter Agentation — LLM & AI Agent Communication Guide

This project is connected to the **Flutter Agentation** inspection engine.
When the Flutter app is running, an embedded Model Context Protocol (MCP) server runs locally at:
- **SSE Transport:** `http://127.0.0.1:4747/sse`
- **HTTP / JSON-RPC Transport:** `http://127.0.0.1:4747/mcp`
- **Health / Status Endpoint:** `http://127.0.0.1:4747/status`

---

## How Any LLM Communicates With the App

### 1. Via MCP (Model Context Protocol)
If your AI agent / IDE supports MCP (Cursor, Claude Code, Antigravity, VS Code Roo/Cline, Windsurf), point its configuration to:
`.flutter_agentation/mcp.json`

The following tools are automatically exposed:
1. **`agentation_get_all_pending`**: Inspect active annotations, widget type, source file path, and line numbers.
2. **`agentation_reply(id, message)`**: Reply directly to the annotation thread inside the Flutter UI.
3. **`agentation_resolve(id)`**: Mark an issue resolved after editing the code.
4. **`agentation_get_app_info()`**: Read platform, route, and resolution info.

---

## 2. Direct HTTP / REST (For Custom LLMs, Scripts & Prompts)
Any LLM that does not use native MCP can inspect and interact using direct HTTP calls:

### Get All Pending Annotations
```bash
curl http://127.0.0.1:4747/pending
```

### Get App Info
```bash
curl http://127.0.0.1:4747/status
```

### JSON-RPC Call (Reply to Annotation)
```bash
curl -X POST http://127.0.0.1:4747/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "agentation_reply",
      "arguments": {
        "id": "ANNOTATION_ID",
        "message": "Fixed the padding in buttons_section.dart"
      }
    }
  }'
```

### JSON-RPC Call (Resolve Annotation)
```bash
curl -X POST http://127.0.0.1:4747/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "agentation_resolve",
      "arguments": {
        "id": "ANNOTATION_ID"
      }
    }
  }'
```
