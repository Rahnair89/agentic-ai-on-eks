# Building Production-Ready AI Agents on Amazon EKS

A worked study of the AWS
[*Building production ready AI Agents on Amazon EKS*](https://catalog.workshops.aws/ai-agents-on-eks/en-US)
workshop — documented module by module, with the design decisions and trade-offs behind each one.

The workshop builds **one agent twice**. A customer service agent for AnyCompany Shop, a fictional
electronics retailer, is deployed on EKS and then evolved along two paths: a fully self-managed
open-source stack, and an integrated stack on Bedrock and AgentCore. The application, the data, and
the observability layer are held constant, so the only variable is who operates the infrastructure.

That controlled comparison is the point of this repo.
**→ [`docs/comparison.md`](docs/comparison.md)** is the main artifact; the module directories below
are the working notes behind it.

---

## The two strategies

Section numbers below (§20, §30-550, and so on) are the workshop's own module numbering, which this
repo's directories mirror — §30-550 is the workshop's `30-integrated-infrastructure/550-evaluation-agentcore`
and this repo's [`30-integrated/550-evaluation-agentcore/`](30-integrated/550-evaluation-agentcore/).

| Layer | Self-managed ([§20](20-self-managed/)) | Integrated ([§30](30-integrated/)) |
|---|---|---|
| Inference | vLLM serving Qwen2.5-3B on Inferentia | Amazon Bedrock (Nova 2 Lite) |
| Model routing | LiteLLM proxy | LiteLLM proxy *(same one)* |
| Agent framework | Strands Agents SDK | Strands Agents SDK *(same code)* |
| Observability | Langfuse, self-hosted | Langfuse, self-hosted *(same project)* |
| Retrieval | Milvus (RAG) | — |
| Memory | Milvus, `conversation_memory` collection | AgentCore Memory |
| Business tools | MCP server on EKS | **MCP server on EKS** *(unchanged)* |
| Sandboxed execution | — | AgentCore Code Interpreter + Browser |
| Multi-agent | A2A protocol | A2A protocol |
| Evaluation | LLM-as-a-Judge in Langfuse | AgentCore Evaluations |
| Knowledge graph | Neo4j | — |

Switching the model plane is a one-line change in the agent: `model_id` flips from
`qwen2-5-3b-neuron` to `nova-lite`, and LiteLLM routes to Bedrock instead of vLLM. Same client class,
same base URL, same code path — at the single-agent and multi-agent level alike.

**MCP stays on both tracks.** Domain-specific tools over your own data are not a sandboxing problem.
That is the workshop's real argument: choose per capability, not per stack.

---

## Architecture

Full diagrams in [`docs/architecture.md`](docs/architecture.md).

```
SELF-MANAGED (§20)                         INTEGRATED (§30)
┌──────────── EKS Auto Mode ───────────┐   ┌──── EKS Auto Mode ────┐
│ Strands agent                        │   │ Strands agent         │
│ MCP server        Milvus   Neo4j     │   │ MCP server (kept)     │
│ Langfuse                             │   │ Langfuse              │
│ ┌─ LiteLLM proxy ──────────────────┐ │   └───────────┬───────────┘
│ │  qwen2-5-3b-neuron → vLLM        │ │       ┌───────▼─────────────────┐
│ │  nova-lite         → Bedrock ────┼─┼──────▶│ Bedrock                 │
│ │  claude-sonnet-4-5 → Bedrock     │ │       │ AgentCore Memory        │
│ └──────────────────────────────────┘ │       │ AgentCore Browser       │
│ vLLM · Qwen2.5-3B on Inferentia      │       │ AgentCore Code Interp.  │
└──────────────────────────────────────┘       │ AgentCore Evaluations   │
                                               └─────────────────────────┘
```

---

## Modules

### [10 · Introduction](10-introduction/)

| Section | Covers |
|---|---|
| [100 · Start with AWS Event](10-introduction/100-start-with-event/) | Workshop Studio account access |
| [200 · Terminal instructions](10-introduction/200-terminal-instructions/) | Browser IDE and terminal |
| [300 · Workshop Structure](10-introduction/300-workshop-structure/) | Pre-provisioned environment, code layout |
| [350 · Sample Application](10-introduction/350-sample-application/) | AnyCompany Shop, data model, chat UI |
| [400 · Agentic AI Patterns](10-introduction/400-agentic-ai-patterns/) | Three strategies and the decision framework |

### [20 · Self-Managed GenAI Strategy](20-self-managed/)

| Section | Capability added |
|---|---|
| [100 · Model Plane: vLLM + LiteLLM](20-self-managed/100-model-plane-vllm-litellm/) | The shared inference endpoint |
| [200 · Agents using Strands](20-self-managed/200-agents-using-strands/) | Agent loop and first tool |
| [300 · Observability using Langfuse](20-self-managed/300-observability-langfuse/) | Tracing every call and decision |
| [400 · RAG with Milvus](20-self-managed/400-rag-milvus/) | Product knowledge from embeddings |
| [500 · Memory using Milvus](20-self-managed/500-memory-milvus/) | Recall across turns in a session |
| [600 · Agent Tool Access (MCP)](20-self-managed/600-agent-tools-mcp/) | Tools move onto the network |
| [700 · Multi-Agent (A2A)](20-self-managed/700-multi-agent-a2a/) | One agent becomes three |
| [750 · Evaluation with LLM-as-a-Judge](20-self-managed/750-evaluation-llm-judge/) | Automated quality scoring |
| [800 · Knowledge Graph with Neo4j](20-self-managed/800-knowledge-graph-neo4j/) | Multi-hop relationship queries |

### [30 · Integrated GenAI Strategy](30-integrated/)

| Section | Change from self-managed |
|---|---|
| [100 · Strands with Bedrock](30-integrated/100-agents-using-strands-with-bedrock/) | One string; LiteLLM does the rest |
| [200 · Observability using Langfuse](30-integrated/200-observability-langfuse/) | Same project, both tracks side by side |
| [300 · Memory using AgentCore](30-integrated/300-memory-agentcore/) | Managed session memory, smaller image |
| [400 · Managed Capabilities](30-integrated/400-managed-tools/) | Sandboxed Python and headless browser |
| [500 · Multi-Agent (A2A)](30-integrated/500-multi-agent-a2a/) | Specialists on Bedrock — MCP kept |
| [550 · Evaluation with AgentCore](30-integrated/550-evaluation-agentcore/) | Managed judging, dual-exported traces |

### [40 · Summary](40-summary/)

What the workshop builds, its own conclusion, and six things worth taking to production.

---

## Four findings worth the read

**1. Evaluation scores measure the instrumentation as much as the agent.**
Run the same LLM-as-a-Judge methodology on both tracks and accuracy scores near zero on the
self-managed agent and 1.0 on the integrated one. The agents behave comparably. The difference is that
the integrated agent emits tool-call spans tagged with `session.id`, so the judge can verify grounding
directly, while the self-managed agent's traces lack tool spans and the judge flags possible
fabrication it cannot rule out. The naive reading — that the managed agent is more accurate — is
exactly the reading a dashboard invites, and it is wrong. Trace coverage sets the ceiling on
evaluation coverage, and evidence you never captured reads identically to evidence of failure.
→ [§20-750](20-self-managed/750-evaluation-llm-judge/) · [§30-550](30-integrated/550-evaluation-agentcore/)

**2. The agent holds no cloud credentials.**
LiteLLM assumes the Bedrock IAM role through Pod Identity, so agent pods stay credential-free — no
`boto3`, no IAM wiring, no AWS SDK. In the integrated multi-agent module the split is sharper still:
all three agents share a ServiceAccount scoped to specific AgentCore resource ARNs and hold no Bedrock
access at all. Two trust boundaries for two kinds of call, and neither lives in the component whose
control flow a language model decides at runtime.
→ [§20-100](20-self-managed/100-model-plane-vllm-litellm/) · [§30-100](30-integrated/100-agents-using-strands-with-bedrock/) · [§30-500](30-integrated/500-multi-agent-a2a/)

**3. Choose per capability, not per stack — and the workshop proves it rather than asserting it.**
In the integrated multi-agent module, MCP stays self-hosted because domain-specific tools over your
own data are not a sandboxing problem, while AgentCore provides the sandboxes because model-generated
code is. One system, one protocol, one conversation. The two tool systems answer different questions:
MCP is about decoupling, sandboxes are about isolation.
→ [§30-500](30-integrated/500-multi-agent-a2a/) · [§30-400](30-integrated/400-managed-tools/)

**4. The swap is free wherever the thing being swapped had no state and no identity attached.**
Inference is a stateless request, so it costs one string. Memory holds customer data under a session
boundary, and the two implementations differ in where that boundary is enforced — a filter expression
in your code, versus a property of the service call and the IAM identity making it. Evaluation reads
telemetry rather than calling the agent, so its integration point is the trace pipeline and that lives
in code. Migration cost tracks state and identity, not vendor.
→ [`docs/comparison.md`](docs/comparison.md)

---

## Running the workshop

The environment is pre-provisioned by Terraform in a Workshop Studio account: EKS in Auto Mode, vLLM
on Inferentia, Langfuse, AgentCore resources, and a browser IDE. Module source ships under
`~/environment/modules/`; Terraform source under `~/environment/terraform/`.

Each module directory here records the commands that module runs, the design decisions behind them,
and the failure modes worth knowing in advance. They document the workshop rather than replacing it.
[`docs/gotchas.md`](docs/gotchas.md) collects every silent-failure mode in one place.

**Cost note.** The self-managed track runs Inferentia nodes plus Milvus, Neo4j, and Langfuse with
their volumes. In a Workshop Studio account this is covered and cleaned up automatically. Reproducing
it in your own account is not free, and stateful components leave volumes and load balancers behind
after a cluster delete — AgentCore resources exist outside the cluster entirely.
[`scripts/verify-teardown.sh`](scripts/verify-teardown.sh) checks for the usual survivors.

---

## Attribution

Documents the AWS workshop *Building production ready AI Agents on Amazon EKS*
(<https://catalog.workshops.aws/ai-agents-on-eks/en-US>). The workshop, its lab source, and the
AnyCompany Shop sample application are AWS's. Command sequences and configuration values are recorded
from the workshop so the notes are reproducible; the write-ups, comparisons, and analysis are mine.
See [`NOTICE`](NOTICE).
