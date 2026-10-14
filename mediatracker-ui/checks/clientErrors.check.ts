// The client error reporter (src/app/main.ts) forwards window "error" events to
// the server. The browser's own "ResizeObserver loop completed with undelivered
// notifications" fires whenever an observer callback changes layout mid-frame —
// unavoidable with dynamic virtual grids and harmless (the notification is
// delivered on the next frame). It must NOT be reported. Run:
// `npm run check:client-errors` (node --experimental-strip-types).
import assert from "node:assert/strict";
import { isIgnorableClientError } from "../src/app/clientErrors.ts";

// 1. Both known ResizeObserver loop wordings are ignored.
{
    assert.equal(
        isIgnorableClientError("ResizeObserver loop completed with undelivered notifications."),
        true,
        "Chromium wording is ignored",
    );
    assert.equal(
        isIgnorableClientError("ResizeObserver loop limit exceeded"),
        true,
        "legacy Firefox/Safari wording is ignored",
    );
}

// 2. Real errors still go through.
{
    assert.equal(
        isIgnorableClientError("Uncaught TypeError: Cannot read properties of null (reading 'id')"),
        false,
        "TypeErrors are reported",
    );
    assert.equal(isIgnorableClientError("Script error"), false, "cross-origin script errors are reported");
    assert.equal(isIgnorableClientError(""), false, "empty message is reported as Script error fallback");
}

console.log("ok   client error reporter skips the benign ResizeObserver loop event only");
