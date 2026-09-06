# 30 · Integrated GenAI Strategy

> Workshop section: [Integrated GenAI Strategy](https://catalog.workshops.aws/ai-agents-on-eks/en-US/30-integrated-infrastructure)

EKS stays for orchestration; self-hosted components are replaced with AWS managed services.

- **Amazon Bedrock** for inference, routed through the same LiteLLM proxy from the self-managed
  track. Agent code stays identical; only `model_id` changes.
- **AgentCore Memory** for session history.
- **AgentCore sandboxes** for isolated tool execution.

## Architecture

```
EKS Cluster (Auto Mode)
├── agents namespace
│   ├── Strands Agent (ServiceAccount: agent)
│   │   OpenAIModel(base_url=LITELLM_BASE_URL, model_id="nova-lite")
│   └── MCP server (business tools stay self-hosted)
├── litellm namespace
│   └── LiteLLM proxy (Pod Identity → Bedrock IAM)
│       ├── Amazon Bedrock              LLM inference via LiteLLM route
│       ├── AgentCore Memory            session history
│       ├── AgentCore Browser           sandboxed web actions
│       └── AgentCore Code Interpreter  sandboxed code execution
└── langfuse namespace
    └── Langfuse (observability, reused from the self-managed track)
```

Langfuse stays self-hosted on both tracks, which makes it the control in the experiment: the variable
is who operates the model plane and the supporting services, not how either is observed.

## Modules

| # | Module | Change from self-managed |
|---|---|---|
| [100](100-agents-using-strands-with-bedrock/) | Agents using Strands with Bedrock | `model_id` flips from `qwen2-5-3b-neuron` to `nova-lite`; LiteLLM handles the rest |
| [200](200-observability-langfuse/) | Observability using Langfuse | Same Langfuse, same project, both tracks side by side |
| [300](300-memory-agentcore/) | Memory Management using AgentCore Memory | Session memory via `bedrock-agentcore` instead of Milvus |
| [400](400-managed-tools/) | Managed Capabilities (Browser + Code Interpreter) | Sandboxed runtimes for model-generated code and live web pages |
| [500](500-multi-agent-a2a/) | Multi-Agent Interaction (A2A) | Same A2A pattern, specialists on Bedrock + AgentCore — **MCP stays self-hosted** |
| [550](550-evaluation-agentcore/) | Evaluation with AgentCore | Managed judging, traces dual-exported to AgentCore Observability |

## The claim, and where it breaks

The workshop's thesis is that agent code is nearly identical across both tracks and only
infrastructure configuration changes.

**It holds cleanly for inference.** Modules 100 and 500 both come down to one string, at the
single-agent and multi-agent level respectively.

**It needs qualifying for memory.** Module 300 says so outright — AgentCore Memory and Milvus solve
different problems, and the honest comparison is against the self-managed *memory* module, not the
RAG one.

**It breaks for evaluation, and that is the interesting one.** Module 550 requires dual-exporting
every span to a second backend with four specific resource attributes attached. That is a real code
change, and the reason is that evaluation reads telemetry rather than calling the agent.

The pattern: **the swap is free wherever the thing being swapped had no state and no identity
attached to it.** Inference is a stateless request. Memory holds customer data under a session
boundary. Evaluation needs a trace history in a particular shape. Cost of migration tracks state and
identity, not vendor.

## The module that makes the argument

[500 · Multi-Agent A2A](500-multi-agent-a2a/) is the one to read if you read one. MCP stays
self-hosted because domain-specific tools over your own data are not a sandboxing problem, while
AgentCore provides sandboxed execution because model-generated code is. Both in one system, behind
one protocol, in the same conversation — which is the workshop's actual argument made concrete rather
than asserted.
