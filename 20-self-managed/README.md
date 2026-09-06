# 20 · Self-Managed GenAI Strategy

> Workshop section: [Self-Managed GenAI Strategy](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure)

Everything runs on EKS. No managed AI services — pods, Helm charts, and Python.

## End state

```
EKS Cluster (Auto Mode)
├── Inferentia Node Pool
│   └── vLLM (Qwen2.5-3B on Neuron)
├── litellm namespace
│   └── LiteLLM proxy (shared model plane for both tracks)
├── General Purpose Nodes
│   ├── Strands Agent
│   ├── Langfuse (observability)
│   ├── Milvus (vector DB / memory)
│   ├── Neo4j (knowledge graph)
│   └── MCP Server (agent tools)
└── Services
    ├── litellm.litellm:4000        OpenAI-compatible proxy
    ├── qwen2-5-3b-neuron.vllm:8000 upstream backend
    ├── langfuse:3000
    ├── milvus:19530
    └── neo4j:7687
```

Components come online progressively — each lab deploys only the piece it needs. Neo4j does not
appear until module 800.

## Labs

| # | Lab | Capability added |
|---|---|---|
| [100](100-model-plane-vllm-litellm/) | Model Plane: vLLM + LiteLLM | The shared inference endpoint every agent calls |
| [200](200-agents-using-strands/) | Agents using Strands | Agent loop and the first tool |
| [300](300-observability-langfuse/) | Observability using Langfuse | Tracing every LLM call and tool invocation |
| [400](400-rag-milvus/) | RAG with Milvus | Product knowledge from real embeddings |
| [500](500-memory-milvus/) | Memory Management using Milvus | Recall across turns in a session |
| [600](600-agent-tools-mcp/) | Agent Tool Access (MCP) | Tools move onto the network |
| [700](700-multi-agent-a2a/) | Multi-Agent Interaction (A2A) | One agent becomes three |
| [750](750-evaluation-llm-judge/) | Evaluation with LLM-as-a-Judge | Automated quality scoring |
| [800](800-knowledge-graph-neo4j/) | Knowledge Graph with Neo4j | Multi-hop questions vector search cannot answer |

## The through-line

Read the track as a sequence of things being pulled out of the agent process. Tools start hardcoded
in `tools.py` and end up on a network service (600). One agent's responsibilities end up split across
three processes (700). Knowledge starts absent, becomes embeddings (400), then becomes typed
relationships (800). Each move buys independent scaling and ownership, and each one costs a component
to run and a network hop to trace.
