# 300 · Observability using Langfuse

> Workshop section: [Observability using Langfuse](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure/300-observability-langfuse)

**Goal:** trace every LLM call, tool invocation, and agent decision, then read one request end to end.

## Why agents need this more than services do

Without traces an agent is a black box. When a customer gets a wrong answer or a response takes ten
seconds, the questions you need answered are: how many LLM calls went into this single query? Did the
agent call the right tool, or hallucinate one that does not exist? Where is the latency — model, tool,
or network? What exactly was sent to the LLM?

None of those are answerable from application logs. A conventional service has one code path per
request that you can read. An agent's path is chosen by the model at runtime, so the trace *is* the
control flow record.

Langfuse ingests OpenTelemetry spans and renders them as hierarchical traces. Think Jaeger or Datadog
APM, but purpose-built for LLM applications: it understands token counts, prompt/completion pairs,
tool call boundaries, and cost attribution natively.

## How it integrates

With the `[otel]` extra, `strands-agents` emits OTel spans for agent loops, LLM calls, and tool
executions automatically. Langfuse ingests them through its OTel-compatible endpoint. No manual
instrumentation.

LiteLLM independently forwards its own proxy-level spans into the same project, so you see both
layers side by side.

## Access

```bash
kubectl get pods -n langfuse
echo "http://$(kubectl get ingress -n langfuse langfuse -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

Sign in with `admin@workshop.local` / `workshop2025`. The **AnyCompany Shop** project and its API keys
(`pk-lf-workshop` / `sk-lf-workshop`) are pre-provisioned.

The web pod may restart once or twice during initial database migration. Expected, not a fault.

## The wiring

Three lines added to the agent, and `tools.py` untouched:

- `get_client()` picks up `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, and `LANGFUSE_BASE_URL` from
  the environment — all three live in `agent-config`
- `auth_check()` turns silent OTel authentication failures into loud ones
- `flush()` after every `/chat` request pushes pending spans before the reply returns

`auth_check()` earns its place. OTel exporters fail silently by design; without an explicit check, a
bad key produces an agent that works perfectly and traces nothing, and you discover it a module later
when the evaluation lab has nothing to score.

```bash
cd ~/environment/modules/20-self-managed/300-observability-langfuse/customer-agent
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent --timeout=120s
```

## Reading a trace

Ask "Where is my order ORD-12345?" and the trace shape is:

```
Trace: "Where is my order ORD-12345?"
└── Agent Loop
    ├── LLM Call (qwen2-5-3b-neuron) — tool call decision
    ├── Tool: lookup_order — ~2ms
    └── LLM Call (qwen2-5-3b-neuron) — final response
    Total: ~2s, 2 LLM calls, 1 tool call
```

Two LLM calls for one question is the agentic pattern made visible: one to decide, one to compose. The
tool itself takes about 2ms. Essentially all latency is inference, which tells you immediately where
optimization effort belongs.

## Two trace names, and why it matters later

The Tracing view holds two kinds of trace:

- `invoke_agent Strands Agents` — the customer conversations, named by Strands for the agent's root span
- `litellm-acompletion` — the proxy's own spans, one per model call, from LiteLLM's separate Langfuse callback

These are not conversations. Module 750 filters evaluators on the trace name, and picking the wrong
one is the most common way to end up with no scores at all. Note the exact string now.

## What this gives you

Every LLM call, tool invocation, and decision captured, entirely in-cluster with no external service.
It also becomes the substrate for module 750 — the evaluation lab scores traces that already exist
rather than instrumenting anything new.
