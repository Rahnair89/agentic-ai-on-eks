# 40 · Summary

> Workshop section: [Summary](https://catalog.workshops.aws/ai-agents-on-eks/en-US/40-summary)

One customer service agent, rebuilt twice: once on pure open source, once mixing in AWS managed
capabilities.

## What the workshop builds

**Shared model plane**

- A single LiteLLM proxy in front of every backend. Agents on both tracks call one OpenAI-compatible
  endpoint, and backend swaps are a one-line `model_id` change.
- Pod Identity on the LiteLLM pod holds Bedrock IAM, so agents stay credential-free for model calls.

**Self-managed infrastructure**

- Qwen2.5-3B served on AWS Inferentia via vLLM, fronted by LiteLLM
- Strands agents wired to the shared model plane
- Langfuse tracing every LLM call and tool invocation, plus LiteLLM's own proxy spans
- Product knowledge via Milvus vector RAG
- Business tools over an MCP server on EKS
- Specialists coordinating over A2A

**Integrated infrastructure**

- vLLM → Amazon Bedrock, a one-line `model_id` swap with LiteLLM doing the rest
- Session memory via AgentCore Memory
- Sandboxed work offloaded to AgentCore Code Interpreter and AgentCore Browser
- Langfuse, MCP, A2A, and the agent code path unchanged — those layers do not care about the backend
- Pod-level AWS auth via EKS Pod Identity, no static credentials in the cluster

## The point

> Each piece is an independent decision. You do not have to pick "EKS + OSS" or "all-managed" as a
> package. Pick per capability, keep orchestration on EKS, and let the model plane absorb the backend
> choice so the agent never has to.

The integrated A2A module is where this stops being a slogan and becomes an artifact: MCP stays
self-hosted for business data while AgentCore provides sandboxed execution, in one system, behind one
protocol, in the same conversation.

## What I would carry into production

Six things, in the order I would argue for them:

1. **Put an OpenAI-compatible gateway in front of inference before you have a second model.** It is
   the reason the swap costs one string, the reason a frontier judge can audit a cheap agent for the
   price of a route entry, and the reason agents hold no cloud credentials. Almost every other
   property in this workshop is downstream of it.

2. **Keep credentials off the agent.** The component whose control flow a language model decides at
   runtime, and which ingests untrusted input by design, should hold an HTTP client and nothing else.
   Inference credentials on the proxy; AgentCore access scoped to specific resource ARNs on the
   ServiceAccount.

3. **Instrument tool calls, not just model calls.** The single most consequential finding across both
   tracks: the self-managed agent scored near zero on accuracy because its traces lacked tool spans,
   and the integrated agent scored 1.0 on the same methodology because its spans were richer. Trace
   coverage sets the ceiling on what can ever be evaluated — and on what you can prove after the fact.

4. **Choose per capability, not per stack.** Managed sandboxes for model-generated code; your own MCP
   server for your own data; self-hosted observability so both tracks stay comparable.

5. **Ask where each boundary is enforced and how you would evidence it.** Session scoping as a filter
   string in application code and as a property of an IAM-authenticated service call are not the same
   control, even when they produce the same behaviour.

6. **Constrain what the model composes.** Fixed Cypher traversals as tools rather than text-to-Cypher;
   parameters passed separately rather than interpolated; sandboxes with no path to internal AWS
   services. The model picks which operation runs and supplies arguments — the set of possible
   operations stays something a human wrote.

## Further reading

Strands Agents SDK · LiteLLM · Amazon Bedrock AgentCore · vLLM on AWS Neuron · Amazon EKS Auto Mode ·
Langfuse

## Cleanup

At an AWS event, resources are cleaned up automatically. Reproducing any of this in your own account
is a different matter — see [`scripts/verify-teardown.sh`](../scripts/verify-teardown.sh) for the
components that survive a cluster delete.
