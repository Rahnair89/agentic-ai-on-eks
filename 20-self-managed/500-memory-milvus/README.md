# 500 · Memory Management using Milvus

> Workshop section: [Memory Management using Milvus](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure/500-memory-milvus)

**Goal:** give the agent conversation memory by storing and replaying the customer's own turns from
the current session.

This is the self-managed counterpart to [module 30-300](../../30-integrated/300-memory-agentcore/),
which does the same job with AgentCore Memory. Same capability, same access pattern, infrastructure
you run yourself.

## Memory and RAG are not the same thing

Same storage engine, different problems:

| | RAG (module 400) | Memory (this module) |
|---|---|---|
| What's stored | Product catalogue + FAQ embeddings (static, shared) | The customer's conversation turns (grows over time) |
| Keyed by | Nothing — one shared catalogue | `actor_id` + `session_id` |
| Retrieval | Vector search: "find similar products" | Recency: "this session's recent turns, in order" |
| Purpose | Ground answers in product knowledge | Continue the conversation with context |

The distinction that matters operationally: the catalogue is shared and static, so a bad retrieval is
a quality problem. Conversation turns are per-customer and grow, so a bad retrieval is a data boundary
problem. Same database, two very different blast radii.

## How it works

1. Each turn — customer question plus agent answer — is stored in a `conversation_memory` collection
   tagged with `actor_id`, `session_id`, and a timestamp
2. On a new message the agent runs a **scalar** query filtered by `actor_id` and `session_id`, sorted
   by time, returning recent turns oldest first
3. Those turns are replayed into the Strands agent as prior messages
4. The agent answers with that context, then records the new turn

`rag_tools.py` is replaced by `memory.py`, and `agent.py` restructures around a streaming `run`
function that hydrates the session's recent turns and records the new one.

## Two lines that carry real weight

**`consistency_level="Strong"` on the read.** Milvus defaults to bounded staleness, which could hide
the turn just written and break multi-turn recall intermittently. This is the kind of bug that
reproduces one time in five and costs an afternoon. If you take one line from this module, take this
one.

**Turns are still embedded on write**, even though retrieval here is a scalar query with no vector
search at all. Milvus is acting as a filtered store. But because the embedding is there, extending to
semantic cross-session recall — "what did this customer ask about last month?" — is a one-line change:
swap the query for a search. Writing the embedding you do not yet need is cheap; backfilling it later
is not.

## Deploy and exercise

```bash
kubectl get pods -n milvus     # same milvus-standalone, etcd, minio from module 400
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent --timeout=180s
```

Two turns in the same browser tab:

1. "Hi, I'd like to check on my order ORD-12345."
2. "Has it shipped yet?"

The agent calls `lookup_order` with ORD-12345 on the second turn without being given the ID again. It
came from the stored turn, not from anything re-typed.

Open a new tab or reload and turn 2 will not find turn 1's context. **That is session scoping working,
not a bug** — and it is worth triggering deliberately, because it is the only direct evidence you get
that the boundary exists.

## In the trace

Each turn now shows a `milvus_memory.recent_turns` span (the read) and a `milvus_memory.record_turn`
span (the write) nested under the root. Memory is read before the model call and written after, and
you can watch it happen.

Instrumenting the memory layer explicitly matters: Strands' OTel covers the agent loop, so anything
you add around the loop is invisible in traces unless you wrap it yourself.

## Result

Session conversation memory on Milvus. The agent carries context across turns instead of treating
each message as the first — same database as the RAG module, a different collection, a recency access
pattern, and semantic recall one line away. Tools are still in-process; module 600 moves them onto
the network.
