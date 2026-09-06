# 400 · RAG with Milvus

> Workshop section: [RAG with Milvus](https://catalog.workshops.aws/ai-agents-on-eks/en-US/20-self-managed-infrastructure/400-rag-milvus)

**Goal:** ground the agent's product answers in the real catalogue using retrieval-augmented
generation over Milvus.

## Milvus

An open-source vector database built for similarity search at scale. Data is stored as
high-dimensional embeddings and queried by proximity. It supports multiple index types (IVF, HNSW,
DiskANN), hybrid search combining vector and scalar filters, and scales from a single-pod standalone
mode to a distributed cluster. Here it runs standalone alongside `etcd` and `minio`.

## Flow

1. Product descriptions stored in Milvus as embeddings
2. Customer asks a product question, the agent calls `search_products`
3. The tool embeds the query with **fastembed** — Qdrant's lightweight library running
   `all-MiniLM-L6-v2` through ONNX runtime — and searches Milvus
4. The LLM writes an answer from the matches

fastembed rather than sentence-transformers means no Python ML framework in the image. The Dockerfile
uses a multi-stage build so the model weights are baked into the final image, which keeps cold start
off the network.

## Two new files

`rag_tools.py` defines the search tool; `seed_products.py` loads the catalogue. `agent.py` gains a
single import. That is the whole diff from module 300.

Three implementation details in `rag_tools.py` are worth carrying into your own code:

- **The embedder and Milvus client are module-level**, loaded once at import and reused across calls.
  Constructing an embedder per request would dominate latency.
- **The Milvus client is not thread-safe.** Pool it for multi-threaded agents. (Contrast with the
  Neo4j driver in module 800, which is thread-safe with built-in pooling — a real difference between
  the two clients that only shows up under concurrency.)
- **The tool docstring's first line is the selection heuristic.** It tells the LLM *when* to pick this
  tool. Tool descriptions are not documentation here; they are prompt engineering, and vague ones
  produce wrong tool choices.

## Seeding

The seeder defines roughly 13 products and FAQs, embeds them, and inserts into a `product_catalog`
collection. Rather than installing fastembed and pymilvus on the IDE for a one-shot job, it ships
inside the agent image and runs as a pod:

```bash
kubectl get pods -n milvus     # milvus-standalone, etcd, minio

IMG=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/customer-agent:milvus
kubectl run milvus-seed --rm -i --restart=Never \
  --image=$IMG --image-pull-policy=Always \
  --env="MILVUS_URI=http://milvus.milvus.svc.cluster.local:19530" \
  --command -- python seed_products.py
```

Expect "Inserted 13 items" and a test search for wireless headphones returning matches. The pod
disappears when the script exits.

Shipping the seeder inside the application image is a pattern worth noting: same dependencies, same
network position, no drift between what seeds the store and what queries it.

## Deploy and exercise

```bash
envsubst < k8s.yaml | kubectl apply -f -
kubectl rollout status deployment/customer-agent --timeout=180s
```

Try: "What's your return policy?", "Do you have any noise cancelling headphones?", "Is the Laptop Pro
under warranty?"

In Langfuse a new `search_products` span appears, typically 50–200ms for embedding plus search. Set
against the ~2s of inference from module 300, retrieval is close to free — a useful ratio to know
before optimizing the wrong layer.

## Result

The agent now has two tools: `lookup_order` for specific orders and `search_products` for catalogue
and FAQ questions. Product knowledge is backed by real embeddings rather than a hardcoded switch
statement. Orders, though, are still mocked inside the agent process — module 600 moves them out.
