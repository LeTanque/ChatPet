# Built-in pet behavior and ChatPet's local adapter

Inspected September 14, 2026. These are implementation observations from the installed app, not a promised public API contract.

## Observed behavior

The installed ChatGPT app bundles `avatar-overlay-native-page-223a4cb71885.js` (SHA-256 prefix `5dd1a1e6a0e7e5c9`). Its local-session status resolver, `bs`, distinguishes:

- Waiting: pending approval, user-input request, or a plan awaiting implementation.
- Failed: a failed latest turn or system-error runtime state.
- Running: an in-progress/resuming turn or active runtime.
- Review: a finished turn that has not been read.
- Idle: no applicable state.

Notification presentation maps running to the laptop sprite row, waiting to the waiting row, failure to failed, and success/review to the review row. Notification priority is waiting, failed, review, then running. The running-left/right rows are triggered by horizontal dragging. The built-in overlay also has greeting, gaze, notifications, voice, and chat controls; these are separate from task-state animation.

The [official features page](https://learn.chatgpt.com/docs/features) did not establish a supported pet-event subscription interface. ChatPet therefore uses an independent, read-only local-file adapter rather than attaching to private app IPC or changing the signed application. No extracted application code is included in this repository.

## Local session evidence

Recent `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` files contained explicit `event_msg` records for `task_started`, `task_complete`, and `turn_aborted`, including timestamps and turn IDs. They also contained `response_item` records with tool-call names, call IDs, and matching output records. Only routing metadata is decoded; prompt, argument, message, and output bodies are not retained by the adapter.

ChatPet translates these records to working, finished, failed/interrupted, and (when a synchronous `request_user_input` call is present) waiting. A matching tool output clears that waiting state. Async questions are not assumed to block a task. Tool output text is never scanned to guess failures or approvals: a command failure is not necessarily a task failure. `task_failed` is also recognized defensively, though the inspected local sample used `turn_aborted` for interrupted turns.

## Intentional limits

- Only local Codex session files are monitored. Browser chats and cloud-only/remote-host tasks are outside this adapter's scope.
- Private in-memory approval dialogs, plan decisions, and unread-review state are not reliably available in these files. Waiting is shown only for a recorded blocking input request. Finished uses a short celebration rather than an unread flag.
- Session-file formats are implementation details and may change. Unknown records are ignored, and missing/unreadable folders produce a visible status. No login or access escalation is attempted by the app.
- At startup the reader reconstructs recent active state from a bounded tail. Mid-turn progress can establish working state if the start marker precedes the tail. It does not replay old completions. A crashed task without a terminal record can appear active until the configurable inactivity timeout (one hour by default).
- Discovery scans metadata every five seconds and tracks the latest 64 session files modified within the last day (or a longer configured timeout). Polling reads appended bytes once per second, at most 2 MB per file per poll. Truncated/replaced files reset their cursor. Partial lines are buffered; lines over 128 KB are skipped. Many enormous content records may delay the next small event until the backlog is consumed.

## Arbitration

Task activity has priority over network and occasional events while enabled: waiting, recent failure, recent completion, then working. Completion/failure reactions default to four seconds and are not retriggered by polling the same record. When there is no current task event, the latest network/occasional state is used. Network failures expire even while task activity takes precedence. Missing session files release task priority. A manual animation preview overrides all sources for its six-second duration.

The Blue Turtle waiting/review images are copied unchanged from the existing pet pack, with their original per-frame durations. Palette-only pets get a question-mark waiting pose and a bouncing celebration fallback. Existing settings gain a disabled task trigger without resetting pet choice, placement, network configuration, or custom mappings.
