# 300 · Workshop Structure

> Workshop section: [Workshop Structure](https://catalog.workshops.aws/ai-agents-on-eks/en-US/10-introduction/300-lab-structure)

## What is already running

The environment is provisioned by Terraform before the first lab. Nothing in the list below is
installed by hand:

- Amazon EKS cluster in **Auto Mode**
- vLLM serving **Qwen2.5-3B** on AWS Inferentia accelerators
- **Langfuse** for observability
- **Amazon Bedrock AgentCore** memory, browser, and code interpreter, pre-provisioned for the
  integrated track
- Browser-based VS Code IDE

Terraform source sits at `~/environment/terraform/` and is readable, which is worth an hour on its
own if you want to see how the AgentCore resources and the LiteLLM routing table are wired.

## Verification

```bash
kubectl get nodes
kubectl get pods -n vllm -l app=qwen2-5-3b-neuron
```

Nodes should report `Ready` and the vLLM pod should be running before any lab starts.

## Code layout

Every module ships its complete end state under `~/environment/modules/`:

```
modules/
├── 20-self-managed/
│   ├── 200-strands-agents/customer-agent/
│   ├── 300-observability-langfuse/customer-agent/
│   ├── 400-rag-milvus/customer-agent/
│   ├── 500-memory-milvus/customer-agent/
│   ├── 600-agent-tools-mcp/{customer-agent,mcp-server}/
│   ├── 700-multi-agent-a2a/a2a-agents/
│   └── 800-knowledge-graph/customer-agent/
└── 30-integrated/
    ├── 100-strands-bedrock/customer-agent/
    ├── 200-observability-langfuse/customer-agent/
    ├── 300-memory-agentcore/customer-agent/
    ├── 400-managed-tools/customer-agent/
    └── 500-multi-agent-a2a/a2a-integrated/
```

This repo mirrors that numbering deliberately, so a directory here maps to the module it documents.

## Resetting

`unzip -o /tmp/modules.zip -d ~/environment/modules/` restores the shipped version of every module
and overwrites local edits. Useful after breaking something, destructive if run casually.
