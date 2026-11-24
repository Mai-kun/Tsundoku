---
name: flutter-agentation-check-mcp
description: >-
  Check Flutter Agentation MCP server connection status across all platforms (Web, Mobile, Desktop) and view runtime details (port, endpoints, connected clients, app route, and pending annotations count).
  Trigger with `/flutter-agentation-check-mcp` or `/check-mcp`.
---

# MANDATORY AGENT DIRECTIVE — EXECUTE IMMEDIATELY
DO NOT summarize or describe Flutter Agentation.
DO NOT recommend one platform over another. Flutter Agentation works seamlessly across all platforms: Web, Android, iOS, Windows, macOS, and Linux.
DO NOT output tutorial text or explore framework code.
You MUST IMMEDIATELY query the MCP status and report the connection details.

## STEP 1: QUERY MCP STATUS
Run the status check immediately using shell or PowerShell:
- Primary Check: `curl.exe -s --max-time 2 http://127.0.0.1:4747/status` (or PowerShell `Invoke-RestMethod -Uri "http://127.0.0.1:4747/status" -TimeoutSec 2`)
- Check Pending Annotations: `curl.exe -s --max-time 2 http://127.0.0.1:4747/pending` and read `.flutter_agentation/annotations.json`

## STEP 2: AUTO-START SERVER IF NOT YET RUNNING
If the status check fails (connection refused or timeout):
The universal MCP server can be auto-started in the background:
- On Windows PowerShell: `Start-Process dart -ArgumentList "run","flutter_agentation:mcp" -WindowStyle Hidden`
- On macOS / Linux: `nohup dart run flutter_agentation:mcp > /dev/null 2>&1 &`
Wait 2 seconds, then re-query `http://127.0.0.1:4747/status`.

## STEP 3: PARSE JSON & PRESENT STATUS REPORT
Examine the returned JSON fields `status`, `appMcpEnabled`, and `mcpConnected`:

### Case A: If MCP is Toggled OFF in App (`status == "disabled"` or `appMcpEnabled == false`):
Display:
> **Flutter Agentation MCP Status: Inactive / Disabled in App (Toggle is OFF)**
>
> - **Server**: Running on port 4747
> - **In-App Toggle**: **OFF** (The grey dot shown in settings)
> - **Pending Pins**: `<annotationsCount>` pins stored
>
> **How to Enable:**
> 1. In your running Flutter app, tap the **gear icon** on the floating toolbar (or go to **Manage MCP & Webhooks**).
> 2. Switch the **MCP Connection** toggle to **ON** (the indicator dot will turn **green**).
> 3. Run `/flutter-agentation-check-mcp` again to confirm live agent sync.

### Case B: If Server is Waiting for App (`status == "waiting"` or `webClientConnected == false` with no app active):
Display:
> **Flutter Agentation MCP Status: Waiting for Flutter App**
>
> - **Server**: Running on port 4747
> - **App Connection**: No active Flutter app is currently sending heartbeats.
> - **Next Step**: Launch your Flutter app on any platform (`flutter run`) and ensure **MCP Connection** is toggled ON.

### Case C: If MCP is Live & Toggled ON (`status == "connected"` or `appMcpEnabled == true`):
Display a structured status card:
- **Status**: Live & Connected (Toggle is ON - Green Dot Active)
- **Auto-Send**: `<autoSendMcp>` (ON: auto-sent / OFF: manual send)
- **Port**: 4747
- **SSE Transport**: `http://127.0.0.1:4747/sse`
- **HTTP / MCP Transport**: `http://127.0.0.1:4747/mcp`
- **Connected Clients**: `<connectedClientsCount>`
- **Active Route**: `<route>` (if available)
- **Theme Mode**: `<themeMode>`
- **Submitted Annotations (Ready for Agent)**: `<submittedCount>` feedback pins
- **Draft Pins (Unsent in App)**: `<unsentCount>` pins waiting to be sent
- **Next Step**:
  - If `<submittedCount> > 0`: Run `/flutter-agentation-review-feedback` to review and implement code fixes.
  - If `<submittedCount> == 0 && <unsentCount> > 0`: Tap the **Send button** (paper plane icon with badge `<unsentCount>`) on the floating toolbar or press **S** to submit your feedback to the agent!

### Case D: If MCP Server Cannot Be Reached (Connection Refused or Timeout):
Display:
> **MCP Server Status: Stopped / Disconnected**
>
> Could not connect to Flutter Agentation on `http://127.0.0.1:4747`.
>
> 1. Start the universal MCP server in your terminal:
>    ```bash
>    dart run flutter_agentation:mcp
>    ```
> 2. On your running Flutter app (any platform: Web, Android, iOS, Windows, macOS, Linux), tap the **Agent Sync** (gear icon) so it shows a **green dot**.
> 3. Run `/flutter-agentation-check-mcp` again.
