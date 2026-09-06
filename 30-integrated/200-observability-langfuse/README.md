# 200 · Observability using Langfuse (integrated)

> Workshop section: [Observability using Langfuse](https://catalog.workshops.aws/ai-agents-on-eks/en-US/30-integrated-infrastructure/200-observability-langfuse)

**Goal:** trace the Bedrock-backed agent into the same Langfuse project and confirm the SDK emits
identical spans whichever backend LiteLLM routes to.

## Same wiring, same project

The integration is the same three-line pattern as the self-managed observability module —
`get_client()`, `auth_check()`, `flush()` — with API keys sourced from the `agent-config` ConfigMap.
`agent.py` reads Langfuse configuration from the environment with nothing hardcoded. The
`[openai,otel]` Strands extras carry over, so the dependency surface is unchanged.

Credentials and project are the same as the self-managed track. **Traces from both tracks land side
by side in the AnyCompany Shop project**, which is what makes the comparison in the next section
possible at all.

```bash
echo "http://$(kubectl get ingress -n langfuse langfuse -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

cd ~/environment/modules/30-integrated/200-observability-langfuse/customer-agent
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent -n agents --timeout=120s
```

## Comparing the two backends

Ask "Where is my order ORD-12345?" then filter by model in Langfuse:

- **Self-managed runs:** model label `qwen2-5-3b-neuron`, latency dominated by inference on a 3B
  Neuron model
- **Integrated runs:** model label `nova-lite`, latency dictated by Bedrock

**The trace structure is identical in both cases:** agent loop → LLM call → tool call → LLM call. The
agent's behaviour did not change; only where the tokens came from did.

That identical shape is the evidence for the workshop's thesis. It is one thing to claim the agent
code is portable across backends and another to see two traces with the same span tree and different
model labels.

## Agent-side versus proxy-side latency

LiteLLM's own spans appear in the same project because the proxy forwards them through its Langfuse
callback. That separation lets you distinguish agent-side latency from proxy-side latency — a useful
breakdown when tuning end-to-end response times, and one you would otherwise have to reconstruct by
subtraction.

It is also the answer to an objection about the proxy pattern. Putting a hop on the critical path of
every inference call is only acceptable if you can measure what that hop costs. Here you can, per
request.

## Result

Observability is the constant across both tracks. The same tool, the same project, the same span
structure — which is exactly what makes it a fair basis for comparing the two strategies rather than
comparing two monitoring setups.
