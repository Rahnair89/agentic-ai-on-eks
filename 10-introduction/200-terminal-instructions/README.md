# 200 · Terminal instructions

> Workshop section: [Terminal instructions](https://catalog.workshops.aws/ai-agents-on-eks/en-US/10-introduction/200-terminal-instructions)

All lab commands run from a browser-based VS Code IDE, not from a local machine.

## Getting in

The Event Dashboard has an **Event Outputs** table with an `IdeUrl` field. That URL opens the Code
Editor and signs you in automatically — the `IdePassword` output is there as a fallback.

## Clipboard

Pasting into a browser terminal needs help from the browser:

- Firefox: `Ctrl+Shift+V` on Windows and Linux, `Cmd+Shift+V` on macOS
- Chrome: grant the clipboard permission prompt when it appears, or paste silently fails

## Why this matters more than it looks

Every module in the workshop starts with a `cd` into a directory under `~/environment/modules/`, and
the source is opened in the IDE rather than typed into heredocs. The IDE is the working environment
for the whole workshop, not just a terminal — the file tree is how you read each module's code.
