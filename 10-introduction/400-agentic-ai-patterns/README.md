# 400 · Agentic AI Patterns on AWS

> Workshop section: [Agentic AI Patterns on AWS](https://catalog.workshops.aws/ai-agents-on-eks/en-US/10-introduction/400-genai-strategies)

Three ways to deploy agents on AWS, distinguished by how much of the stack you operate.

## Strategy 1 — Self-managed on Kubernetes

Open-source models on EKS with control over every layer.

| Component | Service |
|---|---|
| Model inference | vLLM on EKS (Inferentia/GPU) |
| Agent orchestration | Strands Agents SDK |
| Memory | Milvus (vector DB on EKS) |
| Tools | MCP server on EKS |
| Observability | Langfuse on EKS |
| Multi-agent | A2A protocol |

**In favour:** full control over model selection, fine-tuning, and optimization; any open-source or
custom model with no gating; transparent agent logic you can debug at every step; portable across
clouds and on-premises; cost-effective at scale with reserved capacity such as Inferentia or Spot.

**Against:** higher operational overhead for patching, scaling, and monitoring; infrastructure
reliability becomes your problem — node failures, storage, networking; longer time to production;
requires Kubernetes and ML infrastructure expertise on the team.

**Best for** teams with specific model requirements, strict data residency needs, or existing
Kubernetes expertise who want maximum flexibility.

## Strategy 2 — Integrated

Keep the agent framework and orchestration in your own code on EKS; swap self-hosted backends for
managed services.

| Component | Service |
|---|---|
| Model inference | Amazon Bedrock (via LiteLLM proxy) |
| Agent orchestration | Strands Agents SDK (on EKS) |
| Memory | AgentCore Memory |
| Tools | AgentCore Browser, Code Interpreter |
| Observability | Langfuse on EKS |
| Multi-agent | A2A protocol |

**In favour:** the agent code is the same as the self-managed track and only configuration changes;
no model hosting or accelerator management; managed memory and tools cut operational burden; the
LiteLLM proxy makes switching between Bedrock and vLLM a config change; you still own the
orchestration, so agent logic stays fully visible.

**Against:** EKS is still required for the agent pods and observability; Bedrock's model selection is
narrower than open source; AgentCore services are region-dependent; you end up running a mixed
operational model of Kubernetes plus managed services.

**Best for** teams that want to own agent logic and orchestration but offload infrastructure-heavy
components like model serving and data stores.

## Strategy 3 — Fully managed

AWS managed services end to end.

| Component | Service |
|---|---|
| Model inference | Amazon Bedrock |
| Agent orchestration | Bedrock Agents |
| Memory | AgentCore Memory |
| Tools | AgentCore Gateway, Lambda |
| Observability | CloudWatch, Bedrock logging |

**In favour:** fastest path to production with no infrastructure to manage; automatic scaling,
patching, and high availability; native integration with IAM, VPC, and KMS; pay-per-use with no idle
cost.

**Against:** limited to models available in Bedrock; less control over inference parameters and
optimization; orchestration logic is opaque, which makes complex flows harder to debug.

**Best for** teams that want to ship fast, do not need custom models, and prefer operational
simplicity over fine-grained control.

## Decision framework

| Question | Self-managed | Integrated | Fully managed |
|---|---|---|---|
| Need a specific open-source model? | Yes | No | No |
| Team has Kubernetes expertise? | Required | Required | Not required |
| Data must stay in your VPC? | Yes | Partial | Partial |
| Time to production matters most? | Slow | Middle | Best |
| Want cloud-portable architecture? | Yes | Partial | No |
| Complex multi-agent workflows? | Full control | Full control | Limited |

## What the workshop covers

Strategies 1 and 2, hands-on:

- **Self-managed:** vLLM on Inferentia → Strands agent → Langfuse → Milvus → MCP → A2A
- **Integrated:** Bedrock via LiteLLM → Strands agent → Langfuse → AgentCore Memory → AgentCore
  tools → A2A

The agent code stays nearly identical across both. Only infrastructure configuration changes — which
is the workshop's central claim and the thing worth testing as you go.

## Reading this critically

The pros and cons above are the workshop's framing and they are reasonable, but two things sit
underneath them that the table does not say outright.

The first is that "control" and "operational burden" are the same axis viewed from two ends. Every
capability the self-managed track gives you — model choice, data residency, debuggability of the
serving layer — arrives attached to a component you now patch, scale, and page someone about at 3am.
The nine-component end state of the self-managed track is the real cost figure, not the instance
bill.

The second is that the decision is rarely made once for a whole system. The LiteLLM indirection that
makes track-switching a one-line change also makes the choice reversible per model and per route,
which is a stronger argument for the proxy pattern than for either strategy.
