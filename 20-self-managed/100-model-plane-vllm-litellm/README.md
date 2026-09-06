# 100 · Model Plane: vLLM + LiteLLM on EKS

> Workshop section: [Model Plane: vLLM + LiteLLM on EKS](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure/100-vllm-on-eks)

**Goal:** understand the single model endpoint every agent in the workshop calls, on either track.

Nothing is installed here. Both components are already running; this lab is about understanding the
indirection they create.

## Two components, not one

**vLLM** serves the self-hosted model — Qwen2.5-3B on Inferentia. It is a high-throughput serving
engine with continuous batching and paged attention, exposing a chat-completions-style API, running
on the AWS Neuron SDK for Inferentia and Trainium.

**LiteLLM** is a thin OpenAI-compatible proxy that routes by model name. It speaks the OpenAI
chat-completions format on the front and translates to any of 100+ backends on the back.

## The routing table

| `model_id` | Routes to | Used by |
|---|---|---|
| `qwen2-5-3b-neuron` | vLLM on Inferentia | Self-managed track |
| `nova-lite` | Amazon Bedrock (`us.amazon.nova-2-lite-v1:0`) | Integrated track |
| `claude-sonnet-4-5` | Amazon Bedrock (`us.anthropic.claude-sonnet-4-5-20250929-v1:0`) | The judge in module 750 |

```
Agent pod (either track)
  OpenAIModel(base_url=LITELLM_BASE_URL)
        │
        ▼
┌── LiteLLM proxy (litellm namespace) ──┐
│  qwen2-5-3b-neuron  → vLLM            │
│  nova-lite          → Bedrock         │
│  claude-sonnet-4-5  → Bedrock         │
└───┬───────────────────────────────┬───┘
    ▼                               ▼
vLLM on Inferentia            Amazon Bedrock
(Qwen2.5-3B)                  (Pod Identity)
```

## Why this is the most important lab in the workshop

Because every agent calls LiteLLM rather than vLLM or Bedrock directly, switching between the
self-managed and integrated tracks is a one-line change in the agent: flip `model_id` from
`qwen2-5-3b-neuron` to `nova-lite`. Same client class, same base URL, same code path. The proxy
handles the rest, including AWS IAM for Bedrock through Pod Identity on the LiteLLM pod.

That last point deserves emphasis. **Bedrock credentials live on the LiteLLM pod, not the agent pod.**
The agent has no `boto3`, no IAM wiring, and no AWS credentials at all. It talks HTTP to an in-cluster
service. The credential boundary sits at the proxy, which means agent compromise does not directly
yield Bedrock access — and it means agent pods can be scaled, restarted, and redeployed without
touching IAM.

Adding a model — the `claude-sonnet-4-5` judge, for instance — is one more route entry in the same
proxy config. No new infrastructure.

## Verification

```bash
kubectl get pods -n vllm -l app=qwen2-5-3b-neuron
kubectl get pods -n litellm

# Routing table, printed once at startup
kubectl logs deploy/litellm -n litellm | grep -iE -B2 -A3 "qwen|nova-lite|claude-sonnet"
```

The `Set models` block prints only at startup, so on a long-running pod it ages out of the log
buffer. An empty grep result does not mean the routes are missing — the curl tests below are the
definitive check. To force a fresh block: `kubectl rollout restart deploy/litellm -n litellm`.

If LiteLLM pods are not `Running`:

```bash
kubectl rollout restart deploy/litellm -n litellm
kubectl rollout status deploy/litellm -n litellm --timeout=120s
```

## Testing the routes

```bash
LITELLM_URL="http://$(kubectl get ingress -n litellm litellm -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
LITELLM_KEY=$(kubectl get cm agent-config -n default -o jsonpath='{.data.LITELLM_API_KEY}')

curl -s $LITELLM_URL/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen2-5-3b-neuron", "messages": [{"role":"user","content":"What is 2+2?"}], "max_tokens": 100}'
```

Swap `"model"` for `nova-lite` or `claude-sonnet-4-5` and the same payload reaches a different
backend. Same endpoint, same shape, different provider — that is the entire point.

An empty `$LITELLM_URL` means the ALB is still provisioning; wait 60 seconds and re-run. The master
key is a per-deployment random value Terraform writes into the `agent-config` ConfigMap.

## Admin UI

```bash
echo "$LITELLM_URL/ui"
```

Log in with username `admin` and the LiteLLM key as password. Four things are worth clicking:
**Models + Endpoints** (the three routes), **Playground** (compare Qwen, Nova, and the Claude judge
side by side without touching Python), **Logs** (every proxied request with latency and
cached-vs-upstream status — useful for spotting agents that keep asking the same thing), and
**Virtual Keys** (scoped keys with budgets).

## The design lesson

An OpenAI-compatible gateway in front of inference is the single highest-leverage piece of
architecture in this workshop. It gives you one place for model routing, rate limiting, key
management, budget enforcement, cost attribution, and proxy-level tracing. Without it, every agent
hardcodes a provider and model migration becomes a redeploy of everything that calls a model.

It also introduces a hop that must stay available. The proxy is now on the critical path for every
inference call on both tracks, so its availability is the availability of every agent.
