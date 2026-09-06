# 100 · Agents using Strands with Bedrock

> Workshop section: [Agents using Strands with Bedrock](https://catalog.workshops.aws/ai-agents-on-eks/en-US/30-integrated-infrastructure/100-strands-bedrock)

**Goal:** move the same agent onto Amazon Bedrock by changing one value, `model_id`, and confirm
nothing else has to change.

## The one-line swap

Both tracks talk to the same LiteLLM proxy over the OpenAI wire format. LiteLLM routes by model name:

| `model_id` | LiteLLM sends to | Track |
|---|---|---|
| `qwen2-5-3b-neuron` | vLLM on Inferentia | Self-managed |
| `nova-lite` | Amazon Bedrock (Nova 2 Lite) | This module |

No new SDK, no client library, no authentication configuration. `model_id="nova-lite"` is a LiteLLM
alias resolving to `bedrock/us.amazon.nova-2-lite-v1:0`. `LITELLM_BASE_URL` comes from the same
`agent-config` ConfigMap in the `agents` namespace. `tools.py` is unchanged from the self-managed
Strands module.

## Where the credentials live

**LiteLLM assumes the Bedrock IAM role through Pod Identity, so the agent pods stay
credential-free.** No `boto3` in the agent, no IAM wiring, no AWS SDK. Bedrock credentials live on the
LiteLLM pod.

This is the single most transferable design decision in the workshop. The agent — the component whose
control flow is decided by a language model at runtime, the component most exposed to untrusted input
— holds no cloud credentials at all. It makes an HTTP call to an in-cluster service, and the
credential boundary sits at the proxy.

Compare the two failure modes. Credentials on the agent pod: a compromised or manipulated agent has
whatever Bedrock access its role grants. Credentials on the proxy: it has an HTTP endpoint that speaks
one protocol and enforces its own routing, keys, and budgets. The second is a considerably smaller
surface, and it costs nothing extra because the proxy was already there for routing.

## Deploy

```bash
cd ~/environment/modules/30-integrated/100-strands-bedrock/customer-agent
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent -n agents --timeout=120s
```

The `customer-agent:bedrock` image is pre-built in ECR.

## Exercising it

Pick **Customer Agent (Integrated GenAI)** and ask the same questions as the self-managed agent:

- "Hi, I ordered a laptop last week and it still hasn't arrived. My order ID is ORD-12345. Can you help?"
- "I want to return the headphones I bought. Order ORD-11111."

Same questions, different model underneath. Port-forward LiteLLM and watch its logs to see the request
go out to Bedrock.

Deployment and model access can take a minute; a first request that times out is worth one retry
before investigating.

## What the swap does and does not buy

Gone from the cluster: GPU/Inferentia node management, the model server, model weights, and the
capacity planning around all three. The entire self-managed module 100 collapses into a routing table
entry.

Traded away: control over the model, its version cadence, and its cost curve — plus a hard dependency
on regional service availability. The per-hour-versus-per-token shape of the bill also inverts, which
matters more than it sounds at steady high volume.

The agent code did not notice any of it.
