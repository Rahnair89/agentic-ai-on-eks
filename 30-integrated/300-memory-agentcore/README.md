# 300 · Memory Management using AgentCore Memory

> Workshop section: [Memory Management using AgentCore Memory](https://catalog.workshops.aws/ai-agents-on-eks/en-US/30-integrated-infrastructure/300-memory-agentcore)

**Goal:** add Amazon Bedrock AgentCore Memory so the agent recalls earlier turns in a session, without
touching the model plane.

The model plane stays exactly as it was — the same OpenAI-compatible client pointed at LiteLLM with
`model_id="nova-lite"`. Only the memory layer changes.

## Not a direct swap

This is the module where the "same agent, different infrastructure" framing needs qualifying. AgentCore
Memory and Milvus solve different problems:

| | Self-managed: Milvus | Integrated: AgentCore Memory |
|---|---|---|
| What it stores | Product catalogue + FAQ embeddings | Conversation events per customer session |
| Access pattern | Vector search ("find similar products") | Event history, retrieval by session/actor |
| Use case | Retrieval-augmented generation | Session memory and personalization |

Conversational memory and knowledge retrieval are complementary, not substitutes. This module covers
conversational memory, which is what AgentCore Memory is designed for. For knowledge retrieval such as
product catalogue search you would keep Milvus or adopt Amazon Bedrock Knowledge Bases.

The genuine like-for-like comparison is against the self-managed
[Memory Management using Milvus](../../20-self-managed/500-memory-milvus/) module, which implements
the same recent-turns-per-session pattern on infrastructure you run. Both tracks do session memory;
only the self-managed track also does RAG, and that asymmetry is real rather than an omission.

## What it builds

A customer service agent that, across separate invocations for the same customer, remembers what was
asked earlier in the session, recognizes repeat customers, and uses past context to shape responses.

## The resource

Terraform provisions the AgentCore Memory resource and stores its ID in the `agent-config` ConfigMap:

```bash
kubectl get configmap agent-config -n agents -o yaml | grep AGENTCORE
```

`AGENTCORE_MEMORY_ID` and `AGENTCORE_MEMORY_ARN` should both appear. The `agent` ServiceAccount
already holds IAM permissions to write and read events.

## The code

```bash
cd ~/environment/modules/30-integrated/300-memory-agentcore/customer-agent
```

A new `memory.py` — a thin boto3 wrapper, no new SDKs — and `agent.py` restructured around a `run()`
that hydrates past turns and records the new one. Two functions: one persists a turn as an event via
`create_event`, carrying the user and assistant messages as a conversational payload; one returns
recent turns via `list_events`.

Four details that matter:

- **`actorId` is customer identity** (email, customer ID); **`sessionId` is one conversation.** The
  same two-key scoping as the Milvus implementation — but here it is a property of the service and the
  IAM identity calling it, rather than a filter string you wrote.
- **`list_events` returns newest first**, so the code reverses to read chronologically. Off-by-one
  ordering here produces an agent that recalls the conversation backwards.
- **Events expire after 30 days**, set in Terraform. Retention is infrastructure configuration, not
  application logic — which is the right place for it and worth noting for anyone who has to answer a
  data-retention question about an agent.
- **`@observe` wraps each call in a Langfuse span**, so memory reads and writes appear alongside the
  LLM and tool spans. Strands' OTel only covers the agent loop; without this decorator the memory
  calls would be invisible in traces.

That last point is the same lesson as the self-managed memory module, arrived at independently:
anything you add *around* the agent loop has to be instrumented deliberately. It is also precisely the
failure that made accuracy scores low in the LLM-as-a-Judge module — an uninstrumented call is a call
the evaluator cannot see.

## Deploy and exercise

```bash
cd ~/environment/modules/30-integrated/300-memory-agentcore/customer-agent
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent -n agents --timeout=120s
```

Pick **Customer Agent (Integrated GenAI)**. The UI passes a stable `session_id` for every message in
the same browser tab, so turn 2 can recall turn 1:

1. "Hi, I'd like to check on my order ORD-12345."
2. "Has it shipped yet?"

The agent calls `lookup_order` with ORD-12345 on its own, pulled from turn 1's event history. No
prompting, no hints.

Open a new tab or reload and the fresh session ID means turn 2 finds nothing. That is the mechanism
working, not a bug — the same deliberate boundary test as the Milvus version.

## In the trace

Each conversation turn now appears as a single end-to-end trace. The `chat_turn` span is the root,
with four children beneath it: the memory read, the Strands agent loop, the LiteLLM proxy spans, and
the memory write.

Read before the model call, write after — the same structure as the Milvus implementation, which makes
the two directly comparable in the same Langfuse project.

## Inspecting stored events

```bash
MEMORY_ID=$(kubectl get cm agent-config -n agents -o jsonpath='{.data.AGENTCORE_MEMORY_ID}')
SESSION_ID=$(kubectl logs -n agents deployment/customer-agent --tail=200 | grep -oE 'ui-[a-f0-9-]+' | tail -1)

aws bedrock-agentcore list-events \
  --memory-id "$MEMORY_ID" \
  --actor-id "workshop-user" \
  --session-id "$SESSION_ID" \
  --include-payloads
```

Two events, each carrying both turns. Being able to read stored conversation state directly from the
CLI matters for anything that will face a data-subject request or an audit.

## What changed

`memory.py` added as plain boto3 with no new SDKs. The agent wrapped in a `run()` that hydrates
history and records the new turn. Milvus, torch, and sentence-transformers dropped — **the image is
materially smaller.**

That last item is the honest accounting of what managed memory buys: not better recall, but the
removal of an embedding stack, a stateful database, and its volumes from your operational surface. The
capability was the same on both tracks. The thing that changed is what you are responsible for at 3am.

## The governance angle

The question worth asking of a memory layer is not which recalls better. It is where the session
boundary is enforced and how you would prove it held.

On Milvus, scoping is a filter expression in your code — auditable by reading the code, and breakable
by one bad change. On AgentCore Memory, scoping is a property of the service call and the IAM identity
making it — auditable through CloudTrail and IAM policy, and not breakable by an application-level
mistake in the same way.

Neither is automatically better. But they fail differently and they are evidenced differently, and for
anything holding real customer conversations that distinction is the one that will come up in review.
