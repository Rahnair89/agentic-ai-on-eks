# 200 · Agents using Strands

> Workshop section: [Agents using Strands](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure/200-strands-agents)

**Goal:** build and deploy the AnyCompany Shop customer service agent with the Strands Agents SDK,
backed by the in-cluster Qwen2.5-3B model.

## Strands in four concepts

- **Agent** — the loop that sends messages to the LLM and executes tool calls
- **Model** — any OpenAI-compatible endpoint; here LiteLLM routing to vLLM
- **Tools** — Python functions decorated with `@tool` that the agent can invoke
- **System prompt** — instructions shaping the agent's behaviour

The LLM decides which tools to call and in what order. That is the part worth sitting with: the
control flow is chosen at inference time, not written in the code.

## Request path

1. Customer query arrives at the Strands agent
2. Agent sends the prompt through LiteLLM to Qwen2.5-3B on vLLM
3. Model decides to call `lookup_order`
4. Agent executes the tool and returns the result to the model
5. Model generates the final response

## The project

Six files under `~/environment/modules/20-self-managed/200-strands-agents/customer-agent`:
`agent.py` and `tools.py` carry the agent logic and tool definitions; `server.py` is a thin FastAPI
wrapper exposing the agent over HTTP for the chat UI; `Dockerfile`, `requirements.txt`, and
`k8s.yaml` are infrastructure.

The model client is constructed with the OpenAI-compatible Strands class, pointed at the LiteLLM base
URL from the `agent-config` ConfigMap, with `model_id="qwen2-5-3b-neuron"` and modest generation
parameters (`max_tokens` 1024, `temperature` 0.3). Flip that one string to `"nova-lite"` and the
agent is on Bedrock with no other code change — the claim module 30-100 goes on to demonstrate.

Qwen3's extended thinking is disabled at the proxy level rather than in the agent, via
`extra_body.chat_template_kwargs.enable_thinking = false` in the model config. Configuration that
belongs to a model lives with the model route, not scattered through every client.

## Build and deploy

```bash
cd ~/environment/modules/20-self-managed/200-strands-agents/customer-agent
IMG=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/customer-agent:strands
docker build --push -t $IMG .

envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent --timeout=120s
```

This is the only lab where the image is built by hand — every later module ships a pre-built image in
ECR. Doing it once end to end is worth it: source → container → ECR → EKS is the loop you would own
in production.

`k8s.yaml` is a Deployment plus a ClusterIP Service on port 8080. `envFrom` mounts the `agent-config`
ConfigMap, so `LITELLM_BASE_URL` arrives automatically.

**The tagging convention is a good habit worth stealing.** Every module uses a distinct image tag
(`:strands`, `:langfuse`, `:milvus`, `:mcp`, `:graph`). `kubectl describe pod` then tells you exactly
which module's code is running, and a fresh `kubectl apply` rolls the Deployment because the spec
changed — no `rollout restart` needed.

## Exercising it

Open the chat UI, pick **Customer Agent (Self-managed GenAI)**:

- "Hi, I ordered a laptop last week and it still hasn't arrived. My order ID is ORD-12345. Can you help?"
- "I want to return the headphones I bought. Order ORD-11111."
- "Can you check on order ORD-99999?"

The third is the interesting one: a non-existent order, testing whether the agent fails gracefully or
invents an answer. Worth running deliberately rather than skipping — hallucinated order status is the
exact failure the evaluation module later tries to catch.

## What exists now, and what does not

Built: an agent on the self-hosted Qwen2.5-3B model through LiteLLM, a Strands loop handling customer
conversations, a `lookup_order` tool, and a long-running HTTP service the chat UI talks to.

Missing, and each gap names the module that closes it: no observability, so the agent is a black box
(300); no product knowledge, only order lookups (400); mock data hardcoded in the process (600); and
one agent wearing every hat (700).
