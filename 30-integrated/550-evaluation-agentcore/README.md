# 550 · Evaluation with AgentCore

> Workshop section: [Evaluation with AgentCore](https://catalog.workshops.aws/ai-agents-on-eks/en-US/30-integrated-infrastructure/550-evaluation-agentcore)

**Goal:** score the integrated agent's conversations with Amazon Bedrock AgentCore Evaluations, using
two built-in evaluators and one custom retail evaluator.

The managed counterpart to the [self-managed LLM-as-a-Judge module](../../20-self-managed/750-evaluation-llm-judge/),
which wired judging inside Langfuse. Here the judging is a Bedrock service, and **the only agent-side
change is where traces are sent.**

## What the service is

AgentCore Evaluations measures agent performance on accuracy, helpfulness, goal completion, tool
selection, and safety. It converts agent traces to a common format and scores them with
LLM-as-a-Judge. **No ground-truth dataset required** — which is what makes it usable against live
conversation traffic rather than a curated test set.

## The three dimensions

| Dimension | Evaluator | Question it answers | Why it matters |
|---|---|---|---|
| Correctness | `Builtin.Correctness` | Are the facts in the reply consistent with the tool results? | Hallucinated order status or prices erode customer trust |
| Helpfulness | `Builtin.Helpfulness` | Does the reply resolve the customer's request clearly? | A correct-but-vague reply still creates a follow-up contact |
| Accuracy | `cs_accuracy` (custom) | Did the agent ground its answer in a real `lookup_order` result rather than inventing order details? | A retail-specific check the built-ins cannot express |

Two built-ins used as they ship, one custom evaluator written because the domain requires it. The
same mixing strategy as the self-managed track, and the same reasoning: write custom rubrics only
where your case genuinely differs from the generic one.

## Dual-export: the one real architectural change

Every other integrated module traces only to Langfuse. AgentCore Evaluations reads from **AgentCore
Observability** (CloudWatch and X-Ray) instead, so this module's agent exports every OpenTelemetry
span to both.

```
Customer-agent pod (agents namespace)
  Strands → OTel spans
    │
    ├── LangfuseSpanProcessor ──────▶ Langfuse (AnyCompany Shop)   [view unchanged]
    │
    └── OTLPAwsSpanExporter (SigV4) ▶ X-Ray OTLP endpoint
                                       └─ Transaction Search → aws/spans
                                            └─ AgentCore Observability
                                                 └─ AgentCore Evaluations
                                                      Builtin.Correctness
                                                      Builtin.Helpfulness
                                                      cs_accuracy (custom, TRACE level)
```

**Both exporters hang off one global `TracerProvider`.** The Langfuse trace tree is identical to
every other module, and the same spans are queryable in the CloudWatch GenAI Observability console,
which is what the evaluators read.

Dual-export rather than migration is the right call and worth copying. Swapping observability
backends to gain an evaluation feature would have cost every trace view built in the previous six
modules. One provider, two processors, no loss.

## The code

`telemetry.py` is new; `agent.py` gets two small edits to put `session.id` on spans. `tools.py` and
`memory.py` are unchanged.

**Three resource attributes are how AgentCore Evaluations finds the spans:**

- `service.name` — the agent's identity
- `aws.log.group.names` — associates spans with the log group
- `aws.service.type: "gen_ai_agent"` — the eval span-query filters on this
- `cloud.resource_id: "runtime/{AGENT_ID}/eval"` — eval parses the agent id out of this

An agent hosted on AgentCore Runtime gets these for free. An EKS-hosted agent sets them explicitly,
which is the tax for running the agent on your own compute while consuming a managed evaluation
service — modest, but it is the kind of integration seam that only appears when you leave the paved
path.

Two implementation details that will cost an afternoon if missed:

- **The X-Ray endpoint must be set explicitly** (`https://xray.{REGION}.amazonaws.com/v1/traces`).
  The exporter otherwise defaults to `localhost:4318` and spans go nowhere, silently.
- **In Langfuse v4, do not construct `LangfuseSpanProcessor` by hand.** Pass the provider to
  `Langfuse(tracer_provider=...)` and it attaches its own processor. Use the returned client; do not
  call `get_client()`.

## Prerequisites Terraform provisions

The CloudWatch log group traces land in, IAM permissions on the `agent` ServiceAccount to emit spans,
run evaluations, and invoke the judge model, an evaluation execution role, and account-level
CloudWatch Transaction Search.

```bash
kubectl get configmap agent-config -n agents -o jsonpath='{.data.AGENTCORE_LOG_GROUP}'; echo
kubectl get configmap agent-config -n agents -o jsonpath='{.data.AGENTCORE_EVAL_ROLE_ARN}'; echo
```

Expect the log group `/aws/bedrock-agentcore/runtimes/customer-agent-eval` and the eval execution
role ARN.

> **Transaction Search is account-level.** Enabling it routes X-Ray trace segments to CloudWatch Logs
> for the entire account and region, not just this agent. Terraform enables it here. In a shared
> account that is a global setting with a global cost, and it is not the kind of thing to switch on
> from a workshop transcript without telling anyone.

## Deploy and generate traces

Image: `customer-agent:agentcore-eval`.

```bash
cd ~/environment/modules/30-integrated/550-evaluation-agentcore/customer-agent
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent -n agents --timeout=120s
```

Two turns in the chat UI ("Where is my order ORD-12345?" then "Has it shipped yet?"), then confirm
the spans arrived. **Allow 60 to 90 seconds of indexing lag.** Transaction Search ingests OTLP spans
into the `aws/spans` log group, so that is where to look — not the per-agent log group.

```bash
START=$(( ($(date +%s) - 600) * 1000 ))
aws logs filter-log-events --region $AWS_REGION --log-group-name "aws/spans" \
  --start-time "$START" --max-items 200 --query 'events[].message' --output json \
  | jq '[ .[] | fromjson | select(.resource.attributes."service.name" == "customer-agent-eval") ] | length'
```

A non-zero count is required before evaluating.

## Creating the custom evaluator

Evaluator management lives in the `bedrock-agentcore-control` CLI; running an evaluation uses the
data-plane `bedrock-agentcore` CLI. The two built-ins ship with the service and need only their IDs;
`cs_accuracy` is created once.

```bash
aws bedrock-agentcore-control list-evaluators --region $AWS_REGION \
  --query "evaluators[?evaluatorType=='Builtin'].evaluatorId" --output text
```

The custom evaluator config is JSON written to a file: an `llmAsAJudge` block with the QA-auditor
instructions, a `ratingScale` with three numerical labels — **Grounded** (fully grounded in tool
results, no invented details, 1.0), **Partial** (mostly grounded, minor unsupported detail, 0.5), and
**Invented** (invented order details or ignored tool results, 0) — and a `modelConfig` naming
`us.anthropic.claude-sonnet-4-5-20250929-v1:0` as the judge.

```bash
CUSTOM_ID=$(aws bedrock-agentcore-control create-evaluator \
  --region $AWS_REGION \
  --evaluator-name cs_accuracy \
  --level TRACE \
  --description "Retail order-accuracy evaluator (tool-grounded)" \
  --evaluator-config file:///tmp/cs_accuracy_config.json \
  --query 'evaluatorId' --output text)
```

`create-evaluator` returns the `evaluatorId` with a suffix appended (`cs_accuracy-0ILEKmG3jn` or
similar) and status `ACTIVE`. It then appears in the AgentCore console under **Evaluations →
Evaluators** and in `list-evaluators` alongside the 16 built-ins.

**The named rating scale is the notable difference from the Langfuse rubric.** The self-managed judge
returns a bare 0–1 number; this one returns Grounded / Partial / Invented with definitions attached.
A label a reviewer can argue with beats a float they have to interpret, and it makes disagreement
about a score a conversation about a definition.

## Running an evaluation

On-demand evaluation scores one conversation: hand `evaluate` the conversation's spans and an
evaluator, get a score. All CLI, no code.

```bash
# Session to score
SESSION_ID=$(kubectl logs -n agents deployment/customer-agent --tail=100 \
  | grep -oE 'session=[^ ]+' | tail -1 | cut -d= -f2)

# Fetch and shape this session's spans
START=$(( ($(date +%s) - 3600) * 1000 ))
aws logs filter-log-events --region $AWS_REGION --log-group-name "aws/spans" \
  --start-time "$START" --max-items 300 --query 'events[].message' --output json \
  | jq --arg s "$SESSION_ID" \
      '{ sessionSpans: [ .[] | fromjson | select(.attributes."session.id" == $s) ] }' \
  > /tmp/eval_input.json

echo "spans collected: $(jq '.sessionSpans | length' /tmp/eval_input.json)"
TRACE_ID=$(jq -r '.sessionSpans[0].traceId' /tmp/eval_input.json)

# One evaluator per call, so loop
for E in "Builtin.Correctness" "Builtin.Helpfulness" "$CUSTOM_ID"; do
  aws bedrock-agentcore evaluate --region $AWS_REGION \
    --evaluator-id "$E" \
    --evaluation-input file:///tmp/eval_input.json \
    --evaluation-target "{\"traceIds\":[\"$TRACE_ID\"]}" \
    --query 'evaluationResults[0].{evaluator:evaluatorName,score:value,label:label,reason:explanation}' \
    --output json
done
```

`spans collected: 0` means indexing has not finished — wait and re-run.

## The result, and why it settles the §750 question

A run against a shipped-order conversation:

| Evaluator | Score | Reasoning |
|---|---|---|
| `Builtin.Correctness` | 1.0 — Perfectly Correct | Every factual claim matches the tool output |
| `Builtin.Helpfulness` | 1.0 — Above And Beyond | Answers where the order is, with the details the customer needs |
| `cs_accuracy` | 1.0 — Grounded | Called `lookup_order`, no invented details |

**Accuracy scores well here because this agent emits tool-call spans tagged with `session.id`, so the
judge can verify grounding directly. The self-managed §750 agent could not: its traces lack tool
spans, so accuracy scored near zero.**

Same judge methodology. Same underlying question. Opposite scores — and the agents were behaving
comparably. The difference was entirely trace richness.

This is the most important result in the workshop, and it is now demonstrated rather than inferred:

> **Evaluation scores measure the instrumentation as much as the agent.**

The naive reading of the two tracks side by side is that the managed agent is more accurate than the
self-hosted one. That reading is wrong, and it is the reading a dashboard invites. Anyone comparing
agents on evaluation scores has to establish that both are instrumented equivalently first, or the
comparison measures telemetry coverage and calls it quality.

For anyone working on AI governance or model risk, this is the transferable point. An evaluation
pipeline is an evidence pipeline, and evidence you did not capture reads identically to evidence of
failure. "The agent hallucinated" and "we could not prove it didn't" produce the same number and
demand opposite responses.

## The two tracks compared

| | Self-managed (§750) | Integrated (this module) |
|---|---|---|
| Judge | `claude-sonnet-4-5` via LiteLLM, inside Langfuse | AgentCore Evaluations (managed) |
| Trace source | Langfuse | AgentCore Observability (dual-exported) |
| Evaluators | Custom + managed from the Langfuse library | Built-in + custom (`cs_accuracy`) |
| Levels | Trace | Span, trace, or session |
| Runs where | Langfuse UI | `bedrock-agentcore` API and CLI |

Two differences with practical weight. **Levels:** span, trace, or session scoring means you can grade
an individual tool selection, a whole conversation, or a multi-turn session — the self-managed setup
scores traces only. **Where it runs:** a CLI and API rather than a UI means evaluation is scriptable
into CI, and a quality gate that runs in a pipeline is a different thing from a dashboard someone
remembers to check.
