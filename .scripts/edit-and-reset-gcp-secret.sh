#!/bin/bash
set -e

# ---------- [📄 Optional .env Loader] ----------
ENV_FILE="$(dirname "$0")/.env"
if [[ -f "$ENV_FILE" ]]; then
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# ---------- [⚙️ SETTINGS] ----------
KEEP_VERSIONS="${KEEP_VERSIONS:-5}"  # Default: keep 10 latest versions

# ---------- [🌈 COLORS] ----------
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
CYAN="\033[1;36m"
RESET="\033[0m"

# ---------- [🧠 UTILS] ----------
abort()   { echo -e "${RED}❌ $1${RESET}"; exit 1; }
info()    { echo -e "${BLUE}$1${RESET}"; }
success() { echo -e "${GREEN}$1${RESET}"; }
warn()    { echo -e "${YELLOW}$1${RESET}"; }

print_help() {
  echo -e "${CYAN}Usage:${RESET}
  gcpsecret <command> [--secret=NAME] [--project=ID] [--file=FILE]

${CYAN}Commands:${RESET}
  edit        Edit a JSON secret with diff + reset
  print       Pretty-print the secret to stdout
  list        Show all secrets or contents of one
  help        Show this help message

${CYAN}Examples:${RESET}
  gcpsecret edit --secret=my-secret --project=my-proj
  gcpsecret print --secret=api-keys
  gcpsecret list
  gcpsecret list --secret=api-keys"
}

# ---------- [⚙️ SETTINGS] ----------
SECRET_NAME=""
GCP_PROJECT=""
INPUT_FILE=""
KEEP_VERSIONS="${5:-10}"

if [[ -z "$1" ]]; then
  print_help
  exit 0
fi

CMD="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secret=*)  SECRET_NAME="${1#*=}" ;;
    --project=*) GCP_PROJECT="${1#*=}" ;;
    --file=*)    INPUT_FILE="${1#*=}" ;;
    *) ;;
  esac
  shift
done

[[ -z "$SECRET_NAME" && "$CMD" != "help" && "$CMD" != "list" ]] && abort "Missing --secret=NAME"

# ---------- [🔧 COMMON INIT] ----------
TMP_DIR="/tmp/gcpsecret-$SECRET_NAME-$$"
EDIT_FILE="$TMP_DIR/edit.json"
MIN_FILE="$TMP_DIR/min.json"
OLD_FILE="$TMP_DIR/old.json"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ---------- [COMMANDS] ----------
case "$CMD" in
  edit)
    mkdir -p "$TMP_DIR"
    info "🔍 Checking dependencies..."
    for cmd in gcloud jq diff; do command -v $cmd &>/dev/null || abort "$cmd not found"; done

    if gcloud --project="$GCP_PROJECT" secrets describe "$SECRET_NAME" &>/dev/null; then
      info "📦 Secret exists. Downloading..."
      gcloud --project="$GCP_PROJECT" secrets versions access latest --secret="$SECRET_NAME" > "$MIN_FILE"
      jq . "$MIN_FILE" > "$OLD_FILE"
      cp "$OLD_FILE" "$EDIT_FILE"
    else
      warn "📁 Secret does not exist. Creating fresh..."
      echo "{}" > "$OLD_FILE"
      cp "$OLD_FILE" "$EDIT_FILE"
      gcloud --project="$GCP_PROJECT" secrets create "$SECRET_NAME" --replication-policy="automatic"
    fi

    info "📝 Editing: $SECRET_NAME"
    ${EDITOR:-nano} "$EDIT_FILE"

    info "🔍 Validating edited content..."

    if [[ ! -s "$EDIT_FILE" ]]; then
      abort "Edited secret is empty. Aborting."
    fi

    if grep -qP '[\x00-\x08\x0E-\x1F\x80-\xFF]' "$EDIT_FILE"; then
      abort "Binary content detected. Secrets must be plain text or JSON."
    fi

    if jq empty "$EDIT_FILE" >/dev/null 2>&1; then
      info "✅ Valid JSON detected."
      jq -c . "$EDIT_FILE" > "$MIN_FILE"
    else
      abort "❌ Invalid JSON. Secret will not be saved. Please fix syntax and try again."
    fi

    info "📊 Diff:"
    if command -v colordiff &>/dev/null; then
      colordiff -u "$OLD_FILE" "$EDIT_FILE" || true
    else
      diff -u "$OLD_FILE" "$EDIT_FILE" || true
    fi

    if cmp -s "$OLD_FILE" "$EDIT_FILE"; then
      success "✅ No changes detected. Nothing to apply."
      exit 0
    fi

    read -rp "$(echo -e "${YELLOW}❓ Apply changes and create new version? [y/N]: ${RESET}")" CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || abort "Cancelled"

    info "📤 Creating new secret version..."
    gcloud --project="$GCP_PROJECT" secrets versions add "$SECRET_NAME" --data-file="$MIN_FILE"

    NEW_VERSION=$(gcloud --project="$GCP_PROJECT" secrets versions list "$SECRET_NAME" \
      --sort-by=~createTime --limit=1 --format="value(name)")
    NEW_VER_ID="${NEW_VERSION##*/}"
    success "✅ New version added: ${NEW_VER_ID}"

    info "🔒 Disabling all previous enabled versions..."
    gcloud --project="$GCP_PROJECT" secrets versions list "$SECRET_NAME" \
      --filter="state:ENABLED" \
      --format="value(name)" | grep -v "$NEW_VER_ID" | while read -r OLD_VER; do
        OLD_VER_ID="${OLD_VER##*/}"
        info "🚫 Disabling version: $OLD_VER_ID"
        gcloud --project="$GCP_PROJECT" secrets versions disable "$OLD_VER_ID" --secret="$SECRET_NAME" --quiet
      done

    VERSIONS_TO_DELETE=$(gcloud --project="$GCP_PROJECT" secrets versions list "$SECRET_NAME" \
      --sort-by=~createTime --format="value(name)" | tail -n +$((KEEP_VERSIONS + 1)))

    for VER in $VERSIONS_TO_DELETE; do
      VER_ID="${VER##*/}"
      info "🗑 Deleting old version: $VER_ID"
      gcloud --project="$GCP_PROJECT" secrets versions destroy "$VER_ID" --secret="$SECRET_NAME" --quiet
    done

    success "✅ Secret updated, old versions disabled + trimmed."
    ;;

  print)
    info "📤 Fetching secret '$SECRET_NAME'..."
    if gcloud --project="$GCP_PROJECT" secrets versions access latest --secret="$SECRET_NAME" 2>/dev/null | jq .; then
      :
    else
      gcloud --project="$GCP_PROJECT" secrets versions access latest --secret="$SECRET_NAME"
    fi
    ;;

  list)
    if [[ -n "$SECRET_NAME" ]]; then
      info "📤 Showing value of: $SECRET_NAME"
      if gcloud --project="$GCP_PROJECT" secrets versions access latest --secret="$SECRET_NAME" 2>/dev/null | jq .; then
        :
      else
        gcloud --project="$GCP_PROJECT" secrets versions access latest --secret="$SECRET_NAME"
      fi
    else
      info "📋 Listing secrets for project: ${GCP_PROJECT:-[active config]}"
      SECRET_LIST_JSON=$(gcloud --project="$GCP_PROJECT" secrets list --format=json 2>&1) || true

      if echo "$SECRET_LIST_JSON" | grep -q "Permission denied"; then
        abort "❌ Permission denied. You don't have access to project '${GCP_PROJECT}'."
      fi

      SECRET_COUNT=$(echo "$SECRET_LIST_JSON" | jq 'length')

      if [[ "$SECRET_COUNT" -eq 0 ]]; then
        warn "📭 No secrets found in project: ${GCP_PROJECT}"
      else
        printf "${CYAN}%-50s %-15s %-30s${RESET}\n" "NAME" "REPLICATION" "CREATED"
        echo "$SECRET_LIST_JSON" | jq -r '.[] | [.name, .replication.policy, .createTime] | @tsv' \
          | while IFS=$'\t' read -r name repl created; do
              printf "%-50s %-15s %-30s\n" "$name" "$repl" "$created"
            done
      fi
    fi
    ;;

  help|"")
    print_help
    ;;

  *)
    abort "Unknown command: $CMD"
    ;;
esac
