---
name: flutter-agentation-review-feedback
description: >-
  Review all available visual feedback pins and annotations from the running Flutter application,
  display structured feedback details, locate source code, apply code modifications, and mark items resolved.
  Trigger with `/flutter-agentation-review-feedback`, `/review-feedback`, or `/flutter-agentation-fix-feedback`.
---

# MANDATORY AGENT DIRECTIVE — START WORK IMMEDIATELY
DO NOT summarize, describe, or explain the Flutter Agentation workflow or architecture.
DO NOT output conversational filler, tutorials, or guides.

CRITICAL INSTRUCTIONS:
- DO NOT explore, analyze, or list files in the `flutter_agentation` package, `bin/mcp.dart`, or framework internals.
- DO NOT attempt to run or compile the MCP server. The running Flutter app already hosts it.
- DO NOT search for "4747" in the Flutter SDK or package sources.
- YOUR SOLE TASK IS TO RETRIEVE ALL AVAILABLE FEEDBACK, REVIEW IT, AND MODIFY THE USER'S APPLICATION CODE.

## STEP 1: FETCH ALL AVAILABLE FEEDBACK
Attempt the following retrieval methods in priority order until annotations are found:

1. **Local Workspace File (Fastest & Direct)**: Read `.flutter_agentation/annotations.json` in the current project root using `read_file`. Filter for active items where `status != 'resolved'` and `status != 'rejected'`.
2. **HTTP REST Endpoint**: Run shell command `curl.exe -s --max-time 2 http://127.0.0.1:4747/pending` (or PowerShell `Invoke-RestMethod -Uri "http://127.0.0.1:4747/pending" -TimeoutSec 2`). Check `.flutter_agentation/config.json` for custom port if 4747 fails.
3. **Auto-Start Server if stopped**: If the endpoint fails and `.flutter_agentation/annotations.json` does not exist, run:
   - PowerShell: `Start-Process dart -ArgumentList "run","flutter_agentation:mcp" -WindowStyle Hidden`
   - Unix: `nohup dart run flutter_agentation:mcp > /dev/null 2>&1 &`
   Wait 2 seconds and re-check `http://127.0.0.1:4747/pending`.
4. **OS Temp Storage File**: Read `%TEMP%\flutter_agentation_annotations.json` (Windows) or `/tmp/flutter_agentation_annotations.json` (macOS/Linux).
5. **MCP Tool Call**: If tool `agentation_get_all_pending` or `mcp_flutter_agentation_agentation_get_all_pending` is available in your tool declaration list, call it immediately.

## STEP 2: HANDLE RESULTS

### If No Pending Annotations Are Found (count == 0 or empty list):
Check if there are unsent draft annotations in the response (`unsentCount > 0`):
If `unsentCount > 0`:
Output ONLY the following message and stop immediately (do NOT modify code without permission):
> **No submitted feedback annotations found.**
>
> You currently have **`<unsentCount>` draft annotations** in your running app, but **Auto-Send is OFF** and you have not submitted them to the agent yet.
>
> **How to Submit:**
> 1. In your running Flutter app, tap the **Send button** (paper plane icon with badge `<unsentCount>` on the floating toolbar) or press **S**.
> 2. Once submitted, run `/flutter-agentation-review-feedback` again and the agent will implement your requested changes.
> *(Tip: If you want all feedback sent automatically without manually clicking Send, open Settings > Manage MCP & Webhooks and turn ON Auto-Send).*

Otherwise (both count == 0 and unsentCount == 0):
Output ONLY the following message and stop immediately:
> **No pending visual feedback annotations found.**
>
> 1. Ensure your Flutter app is running (`flutter run`).
> 2. Ensure MCP Connection is toggled ON in your app toolbar.
> 3. Click on any widget in your app and add your feedback note.
> 4. If Auto-Send is OFF, tap the Send button (paper plane icon) to submit.
> 5. Run `/flutter-agentation-review-feedback` again.

### If Pending Annotations Are Found:
Display all active feedback items immediately in a clear review table:

| ID | Target Widget | Source Location | Feedback / Comment |
| :--- | :--- | :--- | :--- |
| `<id>` | `<widgetType>` | `<sourceLocation>` | `<comment>` |

## STEP 3: NAVIGATE TO SOURCE & APPLY FIX IMMEDIATELY
For each feedback item:
1. Open and read the source file specified in `sourceLocation` (e.g. `lib/screens/home_page.dart` at the target line) using `read_file`.
2. Locate the target widget and implement the user's requested visual, styling, or logic changes.
3. Save the file. Flutter Hot Reload immediately reflects the updates on screen.

## STEP 4: MARK RESOLVED & REMOVE PIN FROM RUNNING APP
Once the code change has been applied:
- Call tool `agentation_resolve` with `{"annotationId": "<id>", "summary": "<summary of fix>"}`
- Or run command: `curl -s -X PATCH http://127.0.0.1:4747/annotations/<id> -H "Content-Type: application/json" -d "{\"status\": \"resolved\"}"`
- Update `.flutter_agentation/annotations.json` if modifying directly.
- The pin marker is immediately removed from the running panel.
- Present a concise summary with clickable file links: `[FileName.dart](file:///path/to/file#Lline)`.
