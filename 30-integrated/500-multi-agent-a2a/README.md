# 500 · Multi-Agent Interaction (A2A)

> Workshop section: [Multi-Agent Interaction (A2A)](https://catalog.workshops.aws/ai-agents-on-eks/en-US/30-integrated-infrastructure/500-multi-agent-a2a)

**Goal:** split the Bedrock agent into A2A specialists, each riding on Bedrock through LiteLLM and
AgentCore.

Same shape as the [self-managed A2A module](../../20-self-managed/700-multi-agent-a2a/), different
backends underneath.

## What swaps, and the one thing that does not

**MCP stays.** Domain-specific tools do not belong in AgentCore — order lookup against your own data
is not a sandboxing problem. Everything else swaps.

This is the sharpest illustration of the workshop's actual argument. The choice is not "self-managed
stack" versus "managed stack". It is per-capability: managed sandboxes for model-generated code,
your own MCP server for your own business data, and the same protocol gluing them together.

## The three agents

`order_agent.py`, `sandbox_agent.py`, and `orchestrator.py`, each a long-lived HTTP service, plus
`server.py` as the HTTP wrapper. Specialists accept A2A JSON-RPC; the orchestrator exposes `/chat`
for the UI.

Note the roster changed from the self-managed track: Order Agent and Orchestrator carry over, but the
Product Agent (RAG over Milvus) is replaced by a **Sandbox Agent** wrapping the AgentCore Code
Interpreter. The specialists follow the capabilities available on each track rather than being a
like-for-like port.

## The diff against the self-managed version

Near-identical to the self-managed Order Agent — same A2A shape, same MCP client, same model client.
Only two things change: `model_id` becomes `nova-lite` instead of `qwen2-5-3b-neuron`, and the
`AgentCard.url` points into the `agents` namespace.

The MCP tools, `A2AStarletteApplication`, and the executor pattern are all identical. LiteLLM handles
the Bedrock translation transparently, so the agent code is unchanged regardless of provider.

Two agents, two backends, one string of difference. The claim held at the single-agent level in
module 100; it holds at the multi-agent level too.

## Deploy

Images `order-agent:bedrock`, `product-agent:bedrock`, and `orchestrator-agent:bedrock` are pre-built.
The sandbox image is pushed to the `product-agent` repo, reused from the self-managed track — a
naming wrinkle worth knowing before it confuses you at `kubectl describe pod` time.

```bash
envsubst < k8s-specialists.yaml  | kubectl apply -f -
envsubst < k8s-orchestrator.yaml | kubectl apply -f -

kubectl rollout status deployment/mcp-server         -n agents --timeout=120s
kubectl rollout status deployment/order-agent        -n agents --timeout=120s
kubectl rollout status deployment/sandbox-agent      -n agents --timeout=120s
kubectl rollout status deployment/orchestrator-agent -n agents --timeout=120s
```

`k8s-specialists.yaml` also deploys the MCP server into the `agents` namespace, so this module is
self-contained — the self-managed MCP server does not need to be running. The order agent reaches it
at `mcp-server.agents.svc.cluster.local:8080/mcp`, configured through an environment variable.

**All three agents use `serviceAccountName: agent`**, inheriting the Pod Identity binding for
AgentCore. Model calls go out through LiteLLM, which holds the Bedrock IAM role.

Worth pausing on that split. The agents hold an identity scoped to AgentCore resources — memory,
sandboxes — and no Bedrock access at all. Inference credentials stay on the proxy. Two different
trust boundaries for two different kinds of call, and neither one lives in the component whose
control flow a model decides.

## Exercising it

Two turns in the same browser tab:

**Turn 1** — "I want to total up what I spent on orders ORD-12345 and ORD-67890."

The orchestrator fans out: `ask_order_agent` for each order, then `ask_sandbox_agent` to run the
arithmetic. One question, three specialist dispatches, two capabilities.

**Turn 2** — "Has either of them shipped yet?"

No order IDs given. The orchestrator routes correctly by pulling context from the previous turn's
AgentCore Memory events. Memory and multi-agent routing composing correctly is the thing to watch
here — the context that makes turn 2 resolvable was written by a different specialist on turn 1.

## The trace

```
Orchestrator (LiteLLM → Nova)
├── ask_order_agent (A2A → order-agent)
│   └── Order Agent (LiteLLM → Nova)
│       ├── lookup_order (MCP)
│       └── LLM response
├── ask_sandbox_agent (A2A → sandbox-agent)
│   └── Sandbox Agent (LiteLLM → Nova)
│       ├── run_python (AgentCore Code Interpreter)
│       └── LLM response
└── Final LLM response
```

Compared against a self-managed A2A trace: same shape, same spans, different `model_id` labels.
LiteLLM emits its own spans so proxy-side latency stays separable.

**One difference worth verifying yourself.** The self-managed module documents the specialist's work
appearing as a *separate top-level trace*, because the JSON-RPC hop crosses a process boundary. The
trace tree shown for this module nests the specialist work beneath the orchestrator instead. If that
difference is real rather than presentational, it matters — a nested trace is the difference between
reading one incident timeline and correlating two by hand. Compare the two tracks in the same Langfuse
project before relying on either behaviour.

## The workshop's own conclusion

Neither approach is universally better. Each capability is an independent choice: use EKS as the agent
runtime, and select managed or self-hosted components per capability based on operational
requirements, compliance needs, and scaling priorities.

The module demonstrates that rather than asserting it — MCP self-hosted for business data, AgentCore
managed for sandboxed execution, in one system, behind one protocol.
