# 750 · Evaluation with LLM-as-a-Judge

> Workshop section: [Evaluation with LLM-as-a-Judge](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure/750-evaluation-llm-judge)

**Goal:** score every agent conversation on accuracy, helpfulness, and safety by having a stronger
model grade the traces already being collected.

## The gap this closes

A trace tells you *what* the agent did. It does not tell you whether the answer was any good, and
reading conversations by hand does not scale past a few dozen.

The asymmetry is the design: the agent under evaluation runs on the cheap self-hosted
`qwen2-5-3b-neuron`, while the judge is `claude-sonnet-4-5` on Bedrock — the strongest route on the
LiteLLM gateway. A cheap model does the work, a stronger managed model audits it. The agent code does
not change at all.

Note what this required: nothing. Because both models are routes on the same proxy (module 100),
adding a frontier judge to a self-hosted stack was a config entry, not an integration.

## Building on the traces you already have

Langfuse already receives every LLM call and tool invocation. The evaluators read those same traces,
take the `input` (customer query) and `output` (agent reply), and attach a numeric score. Nothing new
gets instrumented.

```
Customer-agent pod ──OTel spans──▶ Langfuse (AnyCompany Shop project)
                                     │  Trace (input / output)
                                     ▼
                                   Evaluators
                                     cs-accuracy   (custom)
                                     Helpfulness   (managed)
                                     cs-safety     (custom)
                                     │  OpenAI API
                                     ▼
                                   LiteLLM → Bedrock (claude-sonnet-4-5)
```

1. The agent writes a trace to Langfuse
2. Each evaluator's target and filter match the trace and fire automatically
3. Langfuse calls the judge model through the LiteLLM gateway
4. The judge returns a 0–1 score plus reasoning, attached back onto the trace

## The three dimensions

| Dimension | Question | Why it matters |
|---|---|---|
| **Accuracy** | Did the agent use order and product data correctly, with no invented details? | Hallucinated order status or prices erode customer trust |
| **Helpfulness** | Is the resolution clear, with concrete next steps? | A correct-but-vague reply still creates a follow-up contact |
| **Safety** | Is the tone professional, with no leaked PII or fabricated policy? | Brand and compliance risk on every customer-facing message |

Accuracy and safety are custom evaluators because the criteria are specific to a tool-using retail
agent. Helpfulness uses Langfuse's managed evaluator, which needs no prompt. Mixing the two is
sensible practice — write custom rubrics only where your domain actually differs from the generic
case.

The custom rubrics are worth reading as artefacts in their own right. `cs-accuracy` asks whether the
agent used tools instead of guessing, whether details are consistent with tool results, whether
anything was invented that no tool returned, and whether the conclusion follows from available data.
`cs-safety` asks about leaking another customer's data, making up policies or refunds the business has
not authorized, tone, and staying in scope — with fabricated guarantees, exposed payment data, and
dismissive tone called out as explicit red flags.

Both are recognisably QA rubrics rather than ML metrics, which is the point: they encode what the
business considers a bad answer.

## Setup, and the three ways it goes wrong

### Trace name filter

Filter on `invoke_agent Strands Agents` — the customer conversations. **Not** `litellm-acompletion`,
which is the proxy's own per-model-call spans. Filtering on the wrong name is the most common way to
end up with zero scores.

If only `litellm-acompletion` traces exist, the deployed agent is not the instrumented one — a plain
build with no Langfuse or OTel wiring produces only proxy spans.

### SSRF allowlist

Langfuse blocks cluster-internal RFC1918 addresses by default as SSRF protection. The judge model
lives at an in-cluster hostname, so that host must be allowlisted or every judge call fails with a
blocked-IP error.

The guard runs in **both** pods — `langfuse-web` validates connections, `langfuse-worker` makes the
judge call when an evaluator fires — so the allowlist has to be present on both. Langfuse also needs
`ENCRYPTION_KEY` to store the connection's API key at rest.

```bash
for d in langfuse-web langfuse-worker; do
  for var in LANGFUSE_LLM_CONNECTION_WHITELISTED_HOST ENCRYPTION_KEY; do
    echo -n "$d / $var: "
    kubectl get deploy "$d" -n langfuse \
      -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='$var')].value}{'\n'}"
  done
done
```

Terraform sets both. If the allowlist line prints nothing:

```bash
kubectl set env deployment/langfuse-web deployment/langfuse-worker -n langfuse \
  LANGFUSE_LLM_CONNECTION_WHITELISTED_HOST=litellm.litellm.svc.cluster.local
kubectl rollout status deployment/langfuse-web -n langfuse
kubectl rollout status deployment/langfuse-worker -n langfuse
```

This allowlists the LiteLLM hostname only; SSRF protection stays on for everything else. A security
control correctly blocking an intended internal call, fixed by narrowing rather than disabling — a
good pattern to copy.

### The judge model version

The judge connection under **Settings → LLM Connections** is named `litellm-judge`, adapter `openai`
(LiteLLM speaks the OpenAI wire format), base URL `http://litellm.litellm.svc.cluster.local:4000/v1`,
custom model `claude-sonnet-4-5`.

**It must be Sonnet 4.5, not 4.6.** Langfuse requests a structured score through the OpenAI
`response_format` JSON-schema mechanism. The pinned LiteLLM version returns Bedrock structured output
in the shape Langfuse expects for a specific set of models including Sonnet 4.5, but not 4.6. On 4.6
the score JSON arrives somewhere Langfuse cannot read it and every evaluation fails with "No output
generated". Moving to 4.6 means upgrading LiteLLM to a version advertising native structured-output
support for it, then updating the route.

A version pin three layers away from the thing that breaks — that is the shape of most real
integration failures, and it is a useful one to have seen once.

## Creating the evaluators

Under **Evaluation → Evaluators**, each evaluator is created through a three-stage wizard: select the
evaluator (create from scratch for custom, or pick Helpfulness from the managed list), confirm the LLM
connection (`litellm-judge` with `claude-sonnet-4-5`), then configure how it runs. Target, filter,
variable mapping, sampling, and backfill all live in that last stage — there is no separate screen
later.

For every evaluator:

- **Target: Traces.** Recent Langfuse versions default to *Observations*, which scores individual LLM
  spans rather than whole conversations. Leaving the default makes the filter and variable mapping
  meaningless. A notice that trace-level evaluators are legacy is informational on current versions.
- **Filter:** Name = `invoke_agent Strands Agents`
- **Sampling:** 100%
- **Execute on new traces:** on
- **Execute on historic traces:** on — this is the backfill, off by default

For custom evaluators, map `{{input}}` to Object Trace / Object Field **Input** and `{{output}}` to
Object Trace / Object Field **Output**. Use the Evaluation Prompt Preview to verify: the customer
query and agent response sections must show *different* text. If both show the query, `{{output}}`
is still mapped to Input.

## The finding

Backfill runs under **Evaluation → Evaluators → cs-accuracy → Log**, each row moving PENDING →
COMPLETED with a score and latency, a few seconds per trace per evaluator.

Helpfulness and safety score high. **Accuracy scores low — and that is the finding rather than a
fault.** The agent's traces record the query and the answer but not the `lookup_order` tool-call span,
so the judge cannot tell whether concrete order details were retrieved or invented, and flags possible
fabrication.

This is the most valuable result in the workshop, and it generalises well beyond it:

> **A judge can only grade what the instrumentation captured.**

The agent was right. The score was low. The gap was observability, not quality. Anyone who reads that
dashboard as an agent-quality metric draws exactly the wrong conclusion and starts tuning a prompt
that was never the problem.

Two implications worth carrying:

1. **Evaluation coverage is bounded by trace coverage.** Deciding what to instrument is deciding what
   can ever be evaluated. Tool-call spans are not an observability nicety; they are the evidence that
   grounding happened.
2. **Low scores need a triage step before they need a fix.** "The agent did badly" and "the judge
   could not see what the agent did" produce identical numbers and require opposite responses.

## Production extensions

Langfuse's APIs on top: alert on low scores through webhooks, export scores to a warehouse, or route
low-scoring traces to a stronger model for a second opinion.

## Result

Automated quality scoring on every customer conversation with a stronger model auditing a cheaper one,
entirely inside the cluster. Custom and managed evaluators mixed. Quality can now be trended over
time, regressions caught, and — because both tracks write to the same Langfuse project — backends
compared on recorded evidence rather than impression.
