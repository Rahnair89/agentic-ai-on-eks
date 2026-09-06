# 600 · Agent Tool Access (MCP)

> Workshop section: [Agent Tool Access (MCP)](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure/600-agent-tools-mcp)

**Goal:** move the agent's tools onto the network — build an MCP server with order and inventory
tools, deploy it on EKS, and have the agent discover it at runtime.

## What MCP changes

The Model Context Protocol is an open protocol for how agents discover and call tools. Instead of
tools being hardcoded in the agent, the agent connects to a server that advertises them.

The consequences are structural rather than functional. Tool logic is decoupled from agent logic, so
tools can be reused across agents and updated without redeploying any agent. And because the tool
server is a separate workload, it gets its own scaling, its own network policy, and its own identity.

That last point is the one worth dwelling on. Tools are where an agent touches real systems — the
order database, the inventory service, anything that matters. Making them an independently deployed
and independently permissioned workload means tool capability can be scoped without touching the
agent, and a compromised agent reaches only what the tool server exposes.

## The server

Built with FastMCP, named "AnyCompany Tools", exposing three tools: `lookup_order`,
`check_inventory`, and `initiate_return`. Each is backed by its own independent mock dataset.

The `@mcp.tool()` decorator works the same way as Strands' `@tool`: write a plain Python function and
FastMCP generates the tool schema from the signature and docstring. `mcp.streamable_http_app()`
returns an ASGI application that uvicorn serves directly.

The symmetry between `@mcp.tool()` and `@tool` is not incidental — it is what makes the migration in
this module a move rather than a rewrite.

```bash
cd ~/environment/modules/20-self-managed/600-agent-tools-mcp/mcp-server
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/mcp-server --timeout=60s
```

## Connecting the agent

`tools.py` is deleted — the mock data now lives in the MCP server. At startup the agent creates an
MCP client over streamable HTTP, calls `list_tools_sync()` to pull the tool schema from the server,
and passes the discovered tools straight into the Agent constructor alongside its remaining local
tool.

**The agent did not know those tools existed until that line ran.** That is the shift: tool inventory
becomes runtime state rather than source code. It is also a new failure mode — an agent that starts
before its tool server is ready discovers nothing, and the symptom is an agent that answers
confidently without calling anything.

The client is held open for the process lifetime. A long-running HTTP server means the connection
stays up across requests; opening a fresh one per request would be painful.

```bash
cd ~/environment/modules/20-self-managed/600-agent-tools-mcp/customer-agent
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent --timeout=180s
```

## The test worth running

"I want to return the headphones from order ORD-11111"

The agent should call `lookup_order`, see that the status is `processing`, and **refuse** to initiate
the return — all visible in Langfuse. This is a two-tool flow where the second tool's use is
conditional on the first tool's result, and the refusal is the correct outcome. An agent that returns
a cheerful confirmation here has failed in a way no exception would catch.

## Result

An MCP server on EKS exposing three tools, an agent that discovers them dynamically at startup rather
than relying on a hardcoded list, and a clean separation of concerns with all tool logic outside the
agent process.

Next the single agent is split into specialists.
