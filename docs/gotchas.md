# Failure modes worth knowing in advance

Collected from across the workshop. Each of these produces a symptom that does not point at its cause.

## Evaluation silently scores nothing — self-managed (§20-750)

**Wrong trace name.** Evaluators must filter on `invoke_agent Strands Agents` — the customer
conversations. `litellm-acompletion` is the proxy's own per-model-call spans, not conversations.
Filtering on the wrong one is the most common way to get zero scores.

**Only proxy traces exist.** If `invoke_agent Strands Agents` traces are absent entirely, the deployed
agent is not the instrumented build. A plain agent with no Langfuse or OTel wiring emits only LiteLLM's
spans.

**SSRF allowlist missing.** Langfuse blocks RFC1918 addresses by default. The judge model is at an
in-cluster hostname, so `LANGFUSE_LLM_CONNECTION_WHITELISTED_HOST` must be set on **both**
`langfuse-web` (validates connections) and `langfuse-worker` (makes the judge call). `ENCRYPTION_KEY`
must also be present to store the connection's API key at rest.

**Wrong evaluator target.** Recent Langfuse versions default new evaluators to *Observations*, which
scores individual LLM spans rather than whole conversations. Set target to **Traces** on every
evaluator or the filter and variable mapping mean nothing.

**Backfill off.** *Execute on historic traces* is off by default. Without it, only conversations
created after the evaluator existed get scored.

**Variable mapping reversed.** Map `{{input}}` to Trace Input and `{{output}}` to Trace Output. Use the
Evaluation Prompt Preview — if the customer query and agent response sections show the same text,
`{{output}}` is still pointing at Input and the judge is grading the question.

**Judge on Sonnet 4.6 instead of 4.5.** Langfuse requests a structured score through the OpenAI
`response_format` JSON-schema mechanism. The pinned LiteLLM version returns Bedrock structured output
in the expected shape for a specific model set including Sonnet 4.5 but not 4.6. On 4.6 every
evaluation fails with "No output generated".

## Evaluation silently scores nothing — integrated (§30-550)

**Spans not indexed yet.** Allow 60 to 90 seconds after chatting. `spans collected: 0` means indexing
has not finished, not that export failed.

**Looking in the wrong log group.** Transaction Search ingests OTLP spans into `aws/spans`. Querying
the per-agent log group (`/aws/bedrock-agentcore/runtimes/customer-agent-eval`) will not show them.

**OTLP endpoint not set explicitly.** `OTLPAwsSpanExporter` defaults to `localhost:4318`. Without an
explicit `https://xray.{REGION}.amazonaws.com/v1/traces`, spans go nowhere and nothing errors.

**Langfuse v4 processor constructed by hand.** Do not build `LangfuseSpanProcessor` yourself. Pass the
provider to `Langfuse(tracer_provider=...)` and use the returned client — do not call `get_client()`.

**Missing resource attributes.** AgentCore Evaluations finds spans by querying `aws/spans` filtered on
`aws.service.type = "gen_ai_agent"` and parsing the agent id out of `cloud.resource_id`. An
EKS-hosted agent must set these explicitly; a Runtime-hosted agent gets them for free.

**Transaction Search is account-level.** Enabling it routes X-Ray trace segments to CloudWatch Logs
for the whole account and region, not just this agent. Fine in a workshop account; a shared-account
decision elsewhere.

## Scores look like an agent-quality difference and are not

The self-managed agent scores near zero on accuracy; the integrated agent scores 1.0 on the same
methodology. **The agents behave comparably** — the integrated one emits tool-call spans tagged with
`session.id` so the judge can verify grounding, and the self-managed one does not. Before comparing
any two agents on evaluation scores, establish that both are instrumented equivalently.

## Memory recalls intermittently

**Milvus bounded staleness.** Without `consistency_level="Strong"` on the read, the turn just written
may not be visible yet and multi-turn recall breaks roughly one time in five.

**AgentCore event ordering.** `list_events` returns newest first. Reverse before replaying or the agent
reads the conversation backwards.

**New browser tab.** Both memory implementations scope on session. A reload or a new tab means a new
`session_id` and no recall. This is the boundary working, not a bug — and it is the only direct
evidence you get that scoping exists.

## Traces missing spans

**Anything outside the agent loop.** Strands' OTel instrumentation covers the agent loop only. Memory
reads and writes need an explicit `@observe` wrapper on both tracks, and so do sandbox tool internals
— without it, the Strands tool span records that `run_python` was invoked but not the code that ran or
the stdout that came back. This is the same omission that produced the near-zero accuracy scores in
§750.

**Silent OTel auth failure.** Exporters fail quietly. Without `auth_check()`, a bad Langfuse key
produces an agent that works perfectly and traces nothing — discovered a module later when there is
nothing to evaluate.

## Model plane

**Empty routing-table grep.** The `Set models` block prints once at startup and ages out of the log
buffer on a long-running pod. Absence proves nothing; use the curl tests or the admin UI. To force a
fresh block: `kubectl rollout restart deploy/litellm -n litellm`.

**Empty `$LITELLM_URL`.** The ALB is still provisioning. Wait 60 seconds.

**First Bedrock request times out.** Deployment and model access can take a minute. Retry once before
investigating.

## Tools

**Agent starts before the MCP server is ready.** Tool discovery happens once at startup via
`list_tools_sync()`. An agent that discovers nothing does not crash — it answers confidently without
calling any tool.

**Milvus client is not thread-safe.** Pool it for multi-threaded agents. The Neo4j driver, by
contrast, is thread-safe with built-in pooling.

**Sandbox latency looks like slow tools.** Session startup dominates, not the work. Browser sessions
are slower than code-interpreter sessions because a fresh isolated browser is created every time. One
session per call is a teaching simplification; production caches per agent or conversation.

**Empty page text from `fetch_webpage`.** JavaScript-heavy pages return a shell rather than content,
and the agent then reasons over nothing. The span output is where you see this.

**Sandbox image in an unexpected repo.** In §30-500 the sandbox agent image is pushed to the
`product-agent` ECR repo, reused from the self-managed track.

## Environment

**Stale AWS console session.** Log out of other AWS accounts before opening the temporary workshop
account.

**Clipboard blocked.** Chrome needs the clipboard permission granted; Firefox needs
`Ctrl+Shift+V` / `Cmd+Shift+V`.

**Reset overwrites local edits.** `unzip -o /tmp/modules.zip -d ~/environment/modules/` restores
shipped module source and discards changes.
