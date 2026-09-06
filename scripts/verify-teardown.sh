#!/usr/bin/env bash
# Run after both cleanup modules. Stateful components leave volumes and load
# balancers behind, and AgentCore resources exist outside the cluster entirely —
# deleting the EKS cluster does not remove them.
set -uo pipefail
REGION="${AWS_REGION:-us-west-2}"

echo "== Clusters =="
aws eks list-clusters --region "$REGION"

echo
echo "== Unattached EBS volumes (Milvus, Neo4j, Langfuse leave these) =="
aws ec2 describe-volumes --region "$REGION" \
  --filters Name=status,Values=available \
  --query 'Volumes[].{ID:VolumeId,GB:Size,Created:CreateTime}' --output table

echo
echo "== Load balancers (Langfuse, LiteLLM, Neo4j Browser, chat UI) =="
aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[].{Name:LoadBalancerName,DNS:DNSName}' --output table

echo
echo "== Inferentia / GPU instances still running =="
aws ec2 describe-instances --region "$REGION" \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[?starts_with(InstanceType,`inf`)||starts_with(InstanceType,`trn`)||starts_with(InstanceType,`g`)||starts_with(InstanceType,`p`)].{ID:InstanceId,Type:InstanceType}' \
  --output table

echo
echo "== ECR repositories (customer-agent, mcp-server, a2a agents) =="
aws ecr describe-repositories --region "$REGION" \
  --query 'repositories[].repositoryName' --output table 2>/dev/null || echo "  none or no access"
