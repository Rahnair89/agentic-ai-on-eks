# 800 · Knowledge Graph with Neo4j

> Workshop section: [Knowledge Graph with Neo4j](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure/800-knowledge-graph)

**Goal:** model the shop as a knowledge graph and answer multi-hop questions by traversing
relationships instead of searching vectors.

## Graph versus vector search

Both are retrieval; they answer different questions.

| | RAG with Milvus (400) | Knowledge graph (this module) |
|---|---|---|
| Data shape | Embeddings — points in vector space | Nodes and typed relationships |
| Query | "What is *similar* to this text?" | "What is *connected* to this thing, and how?" |
| Strength | Fuzzy matching over unstructured text | Multi-hop questions, precise joins |
| Example | "noise cancelling headphones" → product description | "customers who bought X also bought…" → 4-hop traversal |

Neither replaces the other. Production agents often combine them as GraphRAG: vector search finds the
entry-point entity, the graph expands from it.

## The ontology

A knowledge graph without a schema drifts into mush. This one is constrained to five node types and
four relationship types:

```
(:Customer)-[:PLACED]->(:Order)-[:CONTAINS {qty}]->(:Product)
(:Product)-[:IN_CATEGORY]->(:Category)-[:HAS_POLICY]->(:Policy)
```

The data is the same shop data as every other module — the three orders from the MCP module, the
products from the Milvus catalogue — plus a few historical orders so traversals have somewhere to go.
What is new is not the data. It is that **relationships are now first-class and queryable**.

## Four tools, each one fixed traversal

- `lookup_order` — order → items → customer (the same lookup as before, now a graph walk)
- `customer_history` — customer → all orders → items
- `recommend_products` — product → orders containing it → those customers → their other orders →
  co-purchased products (4 hops)
- `product_policies` — product → category → policies

**The LLM picks the tool and fills in parameters; it never writes Cypher.** That keeps a 3B model
reliable. Text-to-Cypher — letting the model generate queries — is a natural extension once the
fixed-tool version works, and the ordering is deliberate: prove the traversals are right before
handing query generation to the model.

This is a general pattern for constraining agent risk. The model chooses *which* query runs and
supplies parameters; it does not compose the query. The blast radius of a bad model decision is
bounded by the set of queries you wrote.

Three implementation notes:

- The four-hop `MATCH` in `recommend_products` is the whole argument for this module: product →
  orders → customers → their other orders → products, expressed as one declarative pattern. Writing
  that against a vector index is not a worse query, it is not a query at all.
- The Neo4j driver is module-level and **thread-safe with built-in pooling** — unlike the Milvus
  client from module 400, which needs pooling for multi-threaded agents.
- Parameters are passed separately, never interpolated into the query string. Same injection rule as
  SQL, and it applies with more force here because a model supplies the values.

`rag_tools.py` is replaced by `graph_tools.py` and the seeder writes nodes and relationships instead
of embeddings. There is no embedding model at all, so the Dockerfile drops the multi-stage fastembed
build and returns to a simple single-stage image — the container gets materially smaller.

## Seed and deploy

```bash
kubectl get pods -n neo4j     # expect neo4j-0
export NEO4J_PASSWORD=$(kubectl get configmap agent-config -o jsonpath='{.data.NEO4J_PASSWORD}')

IMG=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/customer-agent:graph
kubectl run graph-seed --rm -i --restart=Never \
  --image=$IMG --image-pull-policy=Always \
  --env="NEO4J_URI=neo4j://neo4j.neo4j.svc.cluster.local:7687" \
  --env="NEO4J_PASSWORD=$NEO4J_PASSWORD" \
  --command -- python seed_graph.py

envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent --timeout=180s
```

The seeder prints node counts by label and a test traversal showing what Laptop Pro 15 buyers also
bought.

## Seeing the graph

This is the part no other module has: look at the data as a graph. Neo4j Browser is exposed through a
load balancer.

```bash
echo "http://$(kubectl get svc -n neo4j neo4j-lb-neo4j -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "Username: neo4j"
echo "Password: $(kubectl get configmap agent-config -o jsonpath='{.data.NEO4J_PASSWORD}')"
```

Once connected the database panel shows 25 nodes across the five ontology labels and 31
relationships. Then:

```cypher
MATCH (c:Customer)-[r1:PLACED]->(o:Order)-[r2:CONTAINS]->(p:Product)
RETURN c, r1, o, r2, p
```

Customers, orders, and products as draggable nodes; click any one to inspect properties. This is the
same data the agent traverses.

The four-hop recommendation, watched as a path lighting up:

```cypher
MATCH path = (:Product {name: 'Laptop Pro 15'})<-[:CONTAINS]-(:Order)
             <-[:PLACED]-(:Customer)-[:PLACED]->(:Order)-[:CONTAINS]->(rec:Product)
WHERE rec.name <> 'Laptop Pro 15'
RETURN path
```

Being able to *see* the data your agent reasons over is underrated. Every other store in this
workshop is inspected through query results; here you look at the shape directly, and structural
problems become visible rather than inferred.

## Exercising it

- "What do people who bought the Laptop Pro 15 usually buy with it?" — the co-purchase traversal
- "What has Jane Doe ordered before?"
- "What's the warranty on the Noise Cancelling Headphones?" — product → category → policy

The first is the important one: **an answer that does not exist in any single record, only in the
connections.** No document contains it, so no amount of retrieval quality would have produced it.

In Langfuse each turn shows a `graph.*` span with the traversal's inputs and returned rows.

## Result

A knowledge graph with an explicit ontology and an agent whose tools are graph traversals. Multi-hop
questions — co-purchases, customer history, policy-via-category — resolve as single declarative
queries against relationships, the class of question RAG alone cannot answer.

That closes the self-managed track. The integrated track runs the same agent against managed
services, and the only agent-side change is `model_id="nova-lite"`, because LiteLLM does the backend
swap.
