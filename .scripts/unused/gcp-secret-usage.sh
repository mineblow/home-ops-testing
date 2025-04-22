#!/bin/bash

command -v gcloud >/dev/null || { echo >&2 "gcloud not found"; exit 1; }
command -v jq >/dev/null || { echo >&2 "jq not found"; exit 1; }

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
  echo "No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

echo "📦 GCP Secret Manager Usage – Project: $PROJECT_ID"
echo "-------------------------------------------------"

SECRETS_JSON=$(gcloud secrets list --format=json)
TOTAL_SECRETS=$(echo "$SECRETS_JSON" | jq 'length')

ACTIVE_VERSIONS=0

printf "| %-30s | %-10s | %-20s |\n" "Secret Name" "Versions" "Labels"
printf "|%s|\n" "$(printf ' %.0s-' {1..65})"

for ROW in $(echo "$SECRETS_JSON" | jq -r '.[] | @base64'); do
  _jq() {
    echo "$ROW" | base64 --decode | jq -r "$1"
  }

  NAME=$(_jq '.name' | cut -d'/' -f4)
  LABELS=$(_jq '.labels // {} | to_entries[]? | "\(.key)=\(.value)"' | paste -sd "," -)
  LABELS=${LABELS:-"-"}

  VERSIONS=$(gcloud secrets versions list "$NAME" --filter="state=ENABLED" --format="json" | jq 'length')
  ACTIVE_VERSIONS=$((ACTIVE_VERSIONS + VERSIONS))

  printf "| %-30s | %-10s | %-20s |\n" "$NAME" "$VERSIONS" "$LABELS"
done

# Estimate storage cost (first 6 versions are free)
STORAGE_COST=$(awk "BEGIN { printf \"%.2f\", ($ACTIVE_VERSIONS > 6 ? ($ACTIVE_VERSIONS - 6) * 0.06 : 0) }")

echo
echo "🔢 Totals:"
echo "- Total secrets:         $TOTAL_SECRETS"
echo "- Active secret versions: $ACTIVE_VERSIONS"

# 🔍 Count API accesses from Cloud Logging
echo
echo "📊 Fetching Secret Access Logs (last 30d)..."
ACCESS_LOGS=$(gcloud logging read \
  'protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion"' \
  --freshness=30d \
  --format=json)

TOTAL_ACCESSES=$(echo "$ACCESS_LOGS" | jq length)
ACCESS_COST=$(awk "BEGIN { printf \"%.2f\", ($TOTAL_ACCESSES > 10000 ? ($TOTAL_ACCESSES - 10000)/10000*0.03 : 0) }")

echo "- Estimated access ops (30d): $TOTAL_ACCESSES"
echo

# 🔍 Breakdown by secret name
echo "📈 Accesses per secret (last 30d):"
echo "$ACCESS_LOGS" | jq -r '.[] | .resource.labels.secret_id' | sort | uniq -c | sort -nr

echo
echo "💰 Estimated Monthly Cost:"
echo "- Storage:  \$$STORAGE_COST"
echo "- Accesses: \$$ACCESS_COST"

if [ "$STORAGE_COST" = "0.00" ] && [ "$ACCESS_COST" = "0.00" ]; then
  echo "✅ You're still within the free tier!"
fi
