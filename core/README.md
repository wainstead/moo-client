# core

Rust classifier engine for transforming raw MOO text lines into structured events.

## What it does

- Input: raw text lines with optional byte offsets
- Output: JSON events
  - `chat`
  - `arrive`
  - `leave`
  - `system`

## Classifier flow

```text
Incoming DATA bytes from proxy
            |
            v
   [Line reassembly + offsets]
   (split by '\n', track byte position)
            |
            v
    +-------------------------+
    | For each complete line  |
    +-------------------------+
            |
            v
   [Rule 1: Chat pattern?]
   e.g. "<name>: <message>"
      | yes                    no
      v                        v
Event::Chat            [Rule 2: Arrive pattern?]
                               e.g. "<name> has arrived."
                              | yes                    no
                              v                        v
                       Event::Arrive           [Rule 3: Leave pattern?]
                                                    e.g. "<name> has left."
                                                   | yes                no
                                                   v                    v
                                            Event::Leave        Event::System
                                                                  (fallback)
            |
            v
   Structured event stream
   (event type + fields + offset)
```

## Files

- `src/lib.rs` classifier and event types
- `src/main.rs` CLI adapter (`<offset>\t<line>` -> JSON event)
- `tests/classify.rs` classifier test suite
