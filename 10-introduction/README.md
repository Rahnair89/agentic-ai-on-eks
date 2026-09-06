# 10 · Introduction

> Workshop section: [Introduction](https://catalog.workshops.aws/ai-agents-on-eks/en-US/10-introduction)

The workshop builds one customer service agent for a fictional retailer, deploys it on Amazon EKS,
and then evolves it twice: once on a fully self-managed open-source stack, once on AWS managed
services. The end state on either track is a multi-agent system with tracing, memory, network tool
access, and sandboxed execution.

Holding the application constant across both tracks is what makes the two strategies comparable.
That comparison is the substance of this repo — see [`docs/comparison.md`](../docs/comparison.md).

## Contents

| Section | What it covers |
|---|---|
| [100 · Start with AWS Event](100-start-with-event/) | Workshop Studio account access |
| [200 · Terminal instructions](200-terminal-instructions/) | The browser IDE and terminal |
| [300 · Workshop Structure](300-workshop-structure/) | Pre-provisioned environment and code layout |
| [350 · Sample Application](350-sample-application/) | AnyCompany Shop, the data model, the chat UI |
| [400 · Agentic AI Patterns on AWS](400-agentic-ai-patterns/) | The three deployment strategies and when each fits |
