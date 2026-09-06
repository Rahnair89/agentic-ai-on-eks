# 350 · Sample Application

> Workshop section: [Sample Application](https://catalog.workshops.aws/ai-agents-on-eks/en-US/10-introduction/350-sample-application)

## AnyCompany Shop

A fictional online retailer selling electronics and accessories. The agent handles customer
inquiries without routing to a human: order status and tracking, product questions against the
catalogue, inventory checks, return requests, and light arithmetic such as totalling two orders.

The agent starts as a single process that can only look up orders. Each module adds one capability
until it becomes a multi-agent system with tracing, memory, network tools, and sandboxed execution.

## Data model

Three orders recur across every lab:

| Order ID | Customer | Item | Status |
|---|---|---|---|
| ORD-12345 | Jane Doe | Laptop Pro 15 ($1,299.99) | Shipped |
| ORD-67890 | John Smith | Wireless Mouse + 2× USB-C Hub ($129.97) | Delivered |
| ORD-11111 | Alice Johnson | Noise Cancelling Headphones ($249.99) | Processing |

They begin as a hardcoded dictionary in `tools.py` and move to the MCP server in module 600.

Two other sources appear later: a product catalogue of roughly 13 products and FAQs, embedded into
Milvus in module 400; and inventory levels for 10 products, served by the MCP server's
`check_inventory` tool.

Keeping the same three orders across nine modules is a deliberate teaching choice. Because the data
never changes, any difference in agent behaviour between modules is attributable to the
infrastructure change that module introduced, not to the input.

## Capability progression

| Module | New capability | Mechanism |
|---|---|---|
| Strands Agents | Agent loop + `lookup_order` | The model decides when to call the tool |
| Observability | Tracing | Every LLM call, tool invocation, and decision becomes an OTel span |
| Memory (Milvus / AgentCore) | Product knowledge or session memory | Vector search over the catalogue; conversation history across turns |
| Tool Access (MCP / AgentCore) | Network tools + sandboxed execution | MCP server for order and inventory tools; the integrated track adds Code Interpreter and Browser |
| Multi-Agent (A2A) | Specialist routing | An orchestrator dispatches to specialists over A2A |

## The chat UI

A Chainlit web app is pre-deployed with a profile dropdown holding four entries — one for each
combination of track (self-managed, integrated) and mode (single-agent, multi-agent):
`self-managed-agent`, `self-managed-a2a`, `integrated-agent`, `integrated-a2a`.

All four post to the same `/chat` endpoint; only the in-cluster Service they target differs. Profiles
whose Service has not been deployed yet will fail, which is expected early on.

```bash
echo $CHAT_UI_URL
```

The UI holds a stable `session_id` per browser tab. That detail becomes load-bearing in both memory
modules — a new tab means a new session and no recall.
