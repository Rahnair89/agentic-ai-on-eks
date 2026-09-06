# 700 · Multi-Agent Interaction (A2A)

> Workshop section: [Multi-Agent Interaction (A2A)](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure/700-multi-agent-a2a)

**Goal:** split the single agent into specialists that talk over the Agent-to-Agent protocol, with an
orchestrator routing each request.

## Why split

A single agent handles simple workflows, but complexity exposes its limits. As the system prompt
grows, the LLM starts confusing similar tools, and changing one capability means changing the entire
agent. A2A assigns each agent a single responsibility: one prompt, one job.

The failure mode being solved is specific and worth naming — it is not that the agent runs out of
capacity, it is that **tool selection degrades as the tool set grows**. Prompt length and tool count
are the constraint, not throughput.

## The three agents

- **Order Agent** — lookups and returns, via the MCP server from module 600
- **Product Agent** — product and FAQ search, via Milvus
- **Orchestrator** — routes queries to the right specialist over A2A

Each lives in its own file and runs as a long-lived HTTP server. The specialists accept requests
through A2A JSON-RPC; the orchestrator exposes a `/chat` endpoint the UI calls directly.

## The a2a-sdk in three pieces

- **`AgentExecutor.execute(context, event_queue)`** — the core execution loop. Retrieves the user's
  query from the request context and sends the agent's reply back through the event queue.
- **`AgentCard`** — publishes agent metadata at `/.well-known/agent.json`: name, URL, capabilities,
  input and output modes, skills with tags, version, and description. Other agents and clients use it
  for discovery.
- **`A2AStarletteApplication`** — wraps the agent as an ASGI application speaking the A2A JSON-RPC
  wire protocol.

The AgentCard is the interesting artefact. It is a service contract published at a well-known path,
which makes an agent addressable and discoverable the same way an OpenAPI document does for a REST
service. Agent capability becomes something you can enumerate from outside the agent.

## Deploy

```bash
cd ~/environment/modules/20-self-managed/700-multi-agent-a2a/a2a-agents
envsubst < k8s-specialists.yaml  | kubectl apply -f -
envsubst < k8s-orchestrator.yaml | kubectl apply -f -

kubectl rollout status deployment/order-agent        --timeout=120s
kubectl rollout status deployment/product-agent      --timeout=120s
kubectl rollout status deployment/orchestrator-agent --timeout=120s
```

## Exercising the routing

Pick **Multi-Agent (Self-managed GenAI)** and alternate between branches in one conversation:

- "Where is my order ORD-12345?" → Order Agent
- "Do you have any good monitors for working from home?" → Product Agent

Routing is decided on query semantics by the orchestrator's model, not by keyword rules.

## What the trace looks like now — and the thing to notice

In Langfuse the orchestrator's trace shows `ask_order_agent` or `ask_product_agent` as a tool call.
That is the A2A dispatch: from the orchestrator's point of view, another agent is just a tool.

**The specialist's actual work appears as a separate top-level trace**, because the JSON-RPC hop
crosses a process boundary. The end-to-end story of one customer question is now split across two
traces with no parent-child link between them.

This is the real cost of the split, and it is an observability cost rather than a latency one.
Reconstructing what happened means correlating traces by hand. In production this is what trace
context propagation across the A2A hop would be for, and it is worth knowing the gap exists before
you need it during an incident.

## Result

An orchestrator routing on semantics, an Order Agent handling orders and returns via MCP, a Product
Agent doing RAG against Milvus, all three sharing the same model plane through LiteLLM to vLLM, and
every hop traced in Langfuse including LiteLLM's own proxy spans.
