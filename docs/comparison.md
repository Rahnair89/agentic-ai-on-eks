# Self-managed versus integrated, layer by layer

The workshop implements one agent twice. This is what actually differs, and where the
"same code, different infrastructure" framing holds and stops holding.

The short version: **the swap is free wherever the thing being swapped had no state and no identity
attached to it.** Inference is a stateless request, so it costs one string. Memory holds customer data
under a session boundary. Evaluation needs a trace history in a particular shape. Migration cost
tracks state and identity, not vendor.

---

## 1. Model plane

| | Self-managed | Integrated |
|---|---|---|
| Model | Qwen2.5-3B | Amazon Nova 2 Lite |
| Serving | vLLM on Inferentia | Bedrock |
| Runs in cluster | Yes — Inferentia node pool | Nothing |
| You operate | Node capacity, model weights, serving engine, upgrades | An IAM role |
| Cost shape | Per hour, whether or not it serves traffic | Per token |
| Model choice | Anything you can host, no gating | Bedrock catalogue |
| Data path | Stays inside the VPC | Regional API call |
| Agent-side change | — | `model_id: "qwen2-5-3b-neuron"` → `"nova-lite"` |

**The claim holds completely.** One string. Same client class, same base URL, same code path,
`tools.py` untouched. It holds again at the multi-agent level in §30-500, where the entire diff across
three specialist agents is `model_id` and a namespace in the AgentCard URL.

**What makes it hold is the proxy, not the frameworks.** Without an OpenAI-compatible gateway in
front of inference, switching providers is a client-library change in every agent. The indirection
turns a migration into a config edit — and it is also what lets a self-hosted stack borrow a frontier
model for one purpose (the Claude Sonnet judge) without any new infrastructure.

**Where the line falls in practice.** Per-hour versus per-token is the decision that scales. Sustained
high throughput favours reserved accelerator capacity; bursty or low volume favours per-token. The
crossover is workload-specific; the shape of the trade is not. Self-managed converts a variable cost
into a fixed one, and fixed costs are only good at high utilisation.

---

## 2. Memory

| | Milvus (§20-500) | AgentCore Memory (§30-300) |
|---|---|---|
| Access pattern | Scalar query on `actor_id` + `session_id`, sorted by time | `list_events` by `actorId` + `sessionId` |
| Storage | `conversation_memory` collection, turns embedded on write | Conversation events per session |
| Scoping enforced by | A filter expression in your code | The service call and the IAM identity making it |
| Retention | Yours to implement | 30 days, set in Terraform |
| Ordering gotcha | — | `list_events` returns newest first; reverse to read chronologically |
| Consistency gotcha | `consistency_level="Strong"` or the turn just written may be invisible | — |
| Image weight | fastembed / torch / sentence-transformers | boto3 only — materially smaller |
| Operational surface | Milvus + etcd + minio, volumes, backups | None |

**This is where the claim needs qualifying**, and §30-300 says so outright: this is not a direct swap,
because AgentCore Memory and Milvus solve different problems. The genuine like-for-like is against the
Milvus *memory* module — both implement recent-turns-per-session. The self-managed track additionally
does RAG and knowledge-graph retrieval, which the integrated track never covers. That asymmetry is
real: for knowledge retrieval you would keep Milvus or adopt Bedrock Knowledge Bases.

**The difference that matters is not recall quality.** Both work. What changes is where the session
boundary lives:

- **Milvus:** a filter string. Auditable by reading code. Breakable by one bad change, silently, with
  cross-session leakage as the failure mode.
- **AgentCore Memory:** a property of the service call and the calling identity. Auditable through IAM
  policy and CloudTrail. Not breakable the same way by an application-level mistake.

Neither is automatically better. They fail differently and they are evidenced differently — and for
anything holding real customer conversations, "how would you prove the boundary held" is the question
that gets asked in review, not "which recalls better".

**Retention placement is worth copying either way.** On the integrated track expiry is Terraform
configuration, not application logic. A data-retention question then gets answered by reading
infrastructure code rather than auditing an application.

---

## 3. Tools

| | MCP server (§20-600) | AgentCore Browser + Code Interpreter (§30-400) |
|---|---|---|
| What it exposes | Business data: `lookup_order`, `check_inventory`, `initiate_return` | Execution: `run_python`, `fetch_webpage` |
| Where it runs | Your cluster, your network policy | Managed sandbox, no access to internal AWS services |
| Discovery | `list_tools_sync()` against the server at startup | Registered in code alongside local tools |
| Session model | Long-lived connection held for the process lifetime | `start_session` → `invoke` → `stop_session` per call |
| Dominant latency | The tool's own work (~ms) | Session startup, not the work |
| Blast radius | Whatever the tool pod can reach | Sandbox boundary |
| Untrusted input | Whatever your tools return | Live web content and model-generated code, by design |

**These are not alternatives, and §30-500 proves it.** In the integrated multi-agent module, **MCP
stays** — domain-specific tools over your own data do not belong in AgentCore — while AgentCore
provides the sandboxes. One system runs both, behind one protocol.

That is the strongest evidence in the workshop for choosing per capability rather than per stack. The
two tool systems answer different questions:

- **MCP** answers *where should tool logic live so it can be reused, scaled, and permissioned
  independently of the agent?* Its value is decoupling.
- **AgentCore sandboxes** answer *where should code the model wrote actually execute?* Their value is
  isolation.

**The risk asymmetry is the point.** Every tool before §30-400 queried data you control. The code
interpreter executes model-generated code; the browser pulls arbitrary web content into the context
window. Those are the two highest-risk capabilities in the workshop, and the sandbox explicitly has no
route to internal AWS services. Managed sandboxing is the reason to use the service version — not the
ergonomics, which is how the workshop frames it.

**Latency tells you where each fits.** MCP tool calls are milliseconds; sandbox calls are dominated by
session startup, and browser sessions are slower than code-interpreter sessions because a fresh
isolated browser is created every time. The workshop's phrasing is right: the latency *is* the price
of isolation. Production would cache sessions per agent or conversation; the traces tell you when the
roundtrip is worth it.

**One shared failure mode.** Runtime tool discovery means an agent that starts before its MCP server
is ready discovers nothing — and the symptom is an agent that answers confidently without calling
anything, not an exception.

**And one shared instrumentation lesson.** `@observe` stacking under `@tool` is what puts the executed
code and its stdout into the trace; without it you see that a tool ran and nothing about what it did.
For a code interpreter, the code the model wrote is precisely what an incident review needs, and it
exists in your telemetry only because someone added a decorator.

---

## 4. Evaluation

| | LLM-as-a-Judge (§20-750) | AgentCore Evaluations (§30-550) |
|---|---|---|
| Judge | `claude-sonnet-4-5` via LiteLLM, inside Langfuse | AgentCore Evaluations (managed) |
| Trace source | Langfuse | AgentCore Observability, dual-exported |
| Evaluators | `cs-accuracy`, `cs-safety` custom; Helpfulness managed | `Builtin.Correctness`, `Builtin.Helpfulness`, `cs_accuracy` custom |
| Ground truth needed | No | No |
| Scoring levels | Trace | Span, trace, or session |
| Score shape | Numeric 0–1 with reasoning | Named scale — Grounded / Partial / Invented — with definitions |
| Runs where | Langfuse UI | `bedrock-agentcore` API and CLI |
| Agent-side change | None | `telemetry.py` + `session.id` on spans |

**This is the only place the "only configuration changes" claim genuinely breaks**, and the reason is
instructive. Evaluation does not call the agent; it reads the agent's telemetry. So the integration
point is the trace pipeline, and that lives in code. §30-550 requires dual-export to a second backend
with four specific resource attributes attached so the service can find the spans.

Dual-export rather than migration is the right call: swapping observability backends to gain an
evaluation feature would have cost every trace view built in the previous six modules. One
`TracerProvider`, two processors, no loss.

### The finding, which the two tracks together settle

Run the same methodology on both agents and the scores diverge sharply.

**Self-managed (§20-750):** helpfulness and safety score high; **accuracy scores near zero.** The
agent's traces record the query and the answer but not the `lookup_order` tool-call span, so the judge
cannot tell whether concrete order details were retrieved or invented, and flags possible fabrication.

**Integrated (§30-550):** all three evaluators return 1.0. Correctness "Perfectly Correct",
helpfulness "Above And Beyond", `cs_accuracy` "Grounded — called `lookup_order`, no invented details".

**The agents were behaving comparably. The difference was entirely trace richness** — the integrated
agent emits tool-call spans tagged with `session.id`, so the judge can verify grounding directly.
Same judge methodology, richer traces, higher scores.

> **Evaluation scores measure the instrumentation as much as the agent.**

The naive reading of these two numbers side by side is that the managed agent is more accurate than
the self-hosted one. That reading is wrong, and it is exactly the reading a dashboard invites. Anyone
comparing agents on evaluation scores has to establish equivalent instrumentation first, or the
comparison measures telemetry coverage and reports it as quality.

Three consequences worth carrying:

1. **Trace coverage sets the ceiling on evaluation coverage.** Choosing what to instrument is
   choosing what can ever be scored. Tool-call spans are not an observability nicety; they are the
   evidence that grounding happened.
2. **Low scores need triage before they need a fix.** "The agent did badly" and "the judge could not
   see what the agent did" produce identical numbers and demand opposite responses.
3. **An evaluation pipeline is an evidence pipeline.** Evidence you never captured reads identically
   to evidence of failure. For anyone whose job involves demonstrating that a system behaved
   acceptably, that equivalence is the thing to design against.

### Two practical differences beyond the finding

**Scoring levels.** AgentCore scores at span, trace, or session level; the Langfuse setup here scores
traces only. Span-level scoring means you can grade an individual tool selection rather than a whole
conversation, which is a different diagnostic instrument.

**Where it runs.** A CLI and API rather than a UI means evaluation is scriptable into CI. A quality
gate that runs in a pipeline is a categorically different thing from a dashboard someone remembers to
open.

**Named scales beat bare floats.** The custom AgentCore evaluator returns Grounded / Partial /
Invented with definitions attached, where the Langfuse rubric returns a number. A label a reviewer can
argue with is more useful than a float they have to interpret, and it turns disagreement about a score
into a conversation about a definition.

### Three ways the self-managed setup silently produces nothing

Worth knowing in advance: filtering on `litellm-acompletion` instead of `invoke_agent Strands Agents`;
the SSRF allowlist missing from `langfuse-web` or `langfuse-worker`, blocking every in-cluster judge
call; and a judge on Sonnet 4.6 instead of 4.5, where structured output arrives in a shape Langfuse
cannot read. The managed track has its own: a 60–90 second indexing lag, spans landing in `aws/spans`
rather than the per-agent log group, and an OTLP exporter that silently defaults to `localhost:4318`
if the X-Ray endpoint is not set explicitly.

---

## 5. Observability

**Held constant.** Langfuse self-hosted on both tracks, same project, same three-line wiring
(`get_client()`, `auth_check()`, `flush()`), same `[openai,otel]` extras — until §30-550, where the
agent adds a second exporter while keeping the Langfuse view identical.

That constancy is what makes the comparison a comparison rather than two monitoring setups side by
side. The trace structure is identical across backends — agent loop → LLM call → tool call → LLM call
— with only the model label and latency profile differing.

Three details generalise:

- **LiteLLM forwards its own spans into the same project**, so agent-side and proxy-side latency
  separate per request. That is the answer to the obvious objection to the proxy pattern: a hop on the
  critical path is acceptable if you can measure what it costs.
- **Anything outside the agent loop must be instrumented deliberately.** Strands' OTel covers the loop
  only. Memory reads and writes need `@observe` on both tracks; sandbox tool internals need it too.
  The same omission is what produced the near-zero accuracy scores in §750.
- **One `TracerProvider` can feed two backends.** Dual-export is a cheaper answer than migration
  whenever a second system needs your telemetry.

---

## 6. Multi-agent (A2A)

| | Self-managed (§20-700) | Integrated (§30-500) |
|---|---|---|
| Specialists | Order Agent (MCP), Product Agent (Milvus RAG) | Order Agent (MCP), Sandbox Agent (Code Interpreter) |
| Orchestrator | Routes on query semantics | Routes on query semantics |
| Tool source | MCP server | **MCP server — unchanged** |
| Model | Qwen via LiteLLM | Nova via LiteLLM |
| Identity | — | All three agents share `serviceAccountName: agent` |
| Diff | — | `model_id` and the AgentCard namespace |

Same protocol both times: `AgentExecutor`, `AgentCard` at `/.well-known/agent.json`,
`A2AStarletteApplication` speaking JSON-RPC. The specialist roster follows the capabilities available
on each track rather than porting like for like.

**The identity split in the integrated version is worth copying.** All three agents run under a
ServiceAccount scoped to AgentCore resources — memory, sandboxes — and hold no Bedrock access at all;
inference credentials stay on the LiteLLM proxy. Two trust boundaries for two kinds of call, and
neither one lives in the component whose control flow a model decides.

**One difference to verify rather than assume.** The self-managed module documents the specialist's
work appearing as a *separate top-level trace*, because the JSON-RPC hop crosses a process boundary.
The trace tree shown for the integrated module nests specialist work beneath the orchestrator. If that
is a real difference rather than a presentational one it matters a great deal — a nested trace is the
difference between reading one incident timeline and correlating two by hand. Both tracks write to the
same Langfuse project, so this is directly checkable.

---

## When each fits

| Condition | Points toward |
|---|---|
| Data cannot leave the VPC | Self-managed |
| A specific open-weights model is required | Self-managed |
| Sustained high inference volume | Self-managed |
| Existing Kubernetes and ML infrastructure expertise | Self-managed |
| Cloud portability is a hard requirement | Self-managed |
| Small team with no accelerator operations experience | Integrated |
| Bursty or unpredictable load | Integrated |
| Executing model-generated code or fetching untrusted web content | Integrated |
| Retention and access boundaries must be evidenced to auditors | Integrated |
| Evaluation must run as a pipeline gate rather than a dashboard | Integrated |

But the table is the wrong shape for the real decision, which is not made once for a whole system.

## The judgement

The framing that survives the workshop is not open source versus managed. It is that **the
indirection layer is the decision, and the backends behind it are reversible.**

LiteLLM is why the model swap costs one string at both the single-agent and multi-agent level, why a
frontier judge can audit a self-hosted agent for the price of a route entry, and why agents hold no
cloud credentials. Get that layer right and the self-managed-versus-integrated question stops being
architectural and becomes per-workload — which is where it belongs, because the answer differs for
inference, memory, tools, and evaluation inside the same system. The workshop's own summary lands in
the same place: pick per capability, keep orchestration on EKS, and let the model plane absorb the
backend choice so the agent never has to.

§30-500 is the proof rather than the assertion: MCP self-hosted for business data and AgentCore
sandboxes for model-generated code, in one conversation, behind one protocol.

Two places the swap is genuinely not free, and both are instructive. **Memory**, because it holds
customer data under a session boundary, and the two implementations differ in where that boundary is
enforced and how it can be proven. **Evaluation**, because it reads telemetry rather than calling the
agent, so the integration point is the trace pipeline and that lives in code.

Which leaves the finding I would actually take to a team. Across both tracks, the same evaluation
methodology returned near-zero accuracy on one agent and 1.0 on the other, and the agents were
behaving comparably — the difference was whether tool-call spans existed. An evaluation pipeline is an
evidence pipeline. Evidence you never captured is indistinguishable from evidence of failure, and no
amount of judge quality recovers it.
