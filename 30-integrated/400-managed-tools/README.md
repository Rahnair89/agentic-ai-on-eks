# 400 · Managed Capabilities (Browser + Code Interpreter)

> Workshop section: [Managed Capabilities (Browser + Code Interpreter)](https://catalog.workshops.aws/ai-agents-on-eks/en-US/30-integrated-infrastructure/400-managed-tools)

**Goal:** give the agent two managed AgentCore runtimes — Code Interpreter for sandboxed Python, and
Browser for live web pages.

- **Code Interpreter** — sandboxed Python for calculations, data work, or quick reports
- **Browser** — sandboxed headless browser for fetching public web pages

Both occupy the same architectural slot as the MCP server in the self-managed track, but for **code
you do not want running anywhere near your pods**. The model plane is unchanged: same client, same
LiteLLM route, same Nova model.

## Why these two are different from every other tool

Every tool up to this point queried data you control — order records, an inventory table, a product
catalogue. These two do not.

The code interpreter **executes code the model wrote**. The browser **pulls arbitrary web content
into the context window**. Those are the two highest-risk capabilities in the whole workshop, and
they are the ones the integrated track answers with managed sandboxes rather than an in-cluster
service. The sandbox has no access to internal AWS services, which is the entire point: a tool whose
inputs are model-generated should not sit inside your network boundary.

That framing is worth stating explicitly, because the workshop presents these as convenience.
Sandboxing is the reason to use the managed version, not the ergonomics.

## Confirm the resources

```bash
kubectl get configmap agent-tools -n agents -o yaml
```

`AGENTCORE_BROWSER_ID` and `AGENTCORE_CODE_INTERPRETER_ID` should appear. The `agent` ServiceAccount
already holds `StartBrowserSession` and `StartCodeInterpreterSession` scoped to those ARNs.

Note the scoping: permission to start a session against *these specific* sandbox resources, not a
blanket grant. Identity-scoped-to-resource is what makes the sandbox boundary meaningful rather than
decorative.

## The code

```bash
cd ~/environment/modules/30-integrated/400-managed-tools/customer-agent
```

A new `sandbox_tools.py` defines two tools with the `@tool` decorator; `agent.py` registers both
alongside the existing `lookup_order`.

**The session lifecycle is a three-step shape:** `start_*_session` → `invoke` → `stop_*_session` in a
`finally` block. One session per call, which is clearer for teaching; production would cache sessions
per agent or per conversation, since session startup dominates the latency.

`fetch_webpage` follows the same pattern using `BrowserClient` from `bedrock-agentcore-starter-toolkit`,
which handles the Chrome DevTools Protocol WebSocket. Doing that by hand is possible and not worth it.

## The instrumentation detail that matters most

**`@observe` stacks underneath `@tool`.** With it, Langfuse captures the **code that was executed** as
span input and the **stdout that came back** as span output. Without it you would see that the tool
was invoked and nothing about what ran inside the sandbox.

The workshop makes this concrete: expand `sandbox.run_python` in the trace tree and the right panel
shows the exact Python the model generated and the stdout the sandbox returned. The Strands
`run_python` tool span sitting next to it records only that the tool was called.

For a code interpreter this is not a nicety. **The code the model wrote is the thing you would need
in an incident review**, and it exists in your traces only because someone added a decorator. The same
lesson appears in three separate modules of this workshop — anything outside the agent loop is
invisible unless you instrument it deliberately — and this is the instance where the missing data
would matter most.

For `fetch_webpage`, the span input is the URL the model requested and the output is the scraped text
the browser returned through CDP. That output is diagnostically useful in a way that is easy to miss:
it shows you when a JavaScript-heavy page returned an empty shell and the agent reasoned over
nothing.

## Deploy

`k8s.yaml` now mounts two ConfigMaps — `agent-config` (memory and Langfuse) and `agent-tools`
(sandbox IDs). Image: `customer-agent:agentcore-tools`.

```bash
cd ~/environment/modules/30-integrated/400-managed-tools/customer-agent
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent -n agents --timeout=180s
```

## Exercising both tools

**Code Interpreter** — "I want to total up what I spent on orders ORD-12345 and ORD-67890."

The agent calls `lookup_order` twice, then `run_python` with the arithmetic, then answers in natural
language. Worth noticing: the model chose to compute rather than to do the arithmetic itself, which
is exactly the behaviour you want from a model that is unreliable at arithmetic and reliable at
recognising arithmetic.

**Browser** — a request comparing the price of a purchased item against a public product page URL.

**Browser sessions take longer to start than Code Interpreter sessions**, because a fresh isolated
browser is created every time. The latency is the price of isolation — a clean trade, and one the
traces let you measure per call.

## Reading the traces

`run_python` and `fetch_webpage` spans carry tool input (code snippet or URL), tool output (stdout or
page text), and latency **usually dominated by session startup rather than the actual work**.

That last point is the practical output of this module: you can now decide, per tool, whether a
sandbox roundtrip is worth it for a given task. Session caching moves from "an optimisation someone
mentioned" to a number you can point at.

## What changed

`sandbox_tools.py` added, two more tools registered, a second ConfigMap mounted so tool IDs reach the
pod environment. **Agent logic did not move — it still sees tools, not infrastructure.**

That sentence is the integrated track's thesis in miniature. The agent gained the ability to execute
code in an isolated runtime and fetch live web pages, and from inside the agent both arrived as
ordinary Python functions with docstrings.
