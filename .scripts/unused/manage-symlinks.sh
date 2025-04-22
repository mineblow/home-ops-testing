#!/bin/bash
set -e

# ---------- [🌈 COLORS] ----------
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
CYAN="\033[1;36m"
RESET="\033[0m"

# ---------- [🧠 CONFIGURATION] ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(realpath "$SCRIPT_DIR/..")"
SCOPE="${1:-terraform}"
LOG_FILE="$REPO_ROOT/logs/symlink.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo -e "${CYAN}📍 Script location: $SCRIPT_DIR${RESET}"
echo -e "${BLUE}📦 Repo root: $REPO_ROOT${RESET}"
echo -e "${YELLOW}🧪 Running in dry-run mode. No changes applied yet.${RESET}"
echo -e "${BLUE}📄 Logging to: $LOG_FILE${RESET}"
echo -e "${BLUE}🔍 Target scope: $SCOPE${RESET}"
echo

# ---------- [📦 DEFINE SYMLINK TARGETS] ----------
declare -A SYMLINK_MAP
if [[ "$SCOPE" == "terraform" || "$SCOPE" == "all" ]]; then
  ENVIRONMENTS=("homelab/ubuntu")
  for ENV in "${ENVIRONMENTS[@]}"; do
    ENV_PATH="$REPO_ROOT/terraform/environments/$ENV"

    # Symlinks created in env dir pointing to terraform root
    TARGET1="$ENV_PATH/credentials.auto.tfvars"
    TARGET2="$ENV_PATH/credentials.variables.tf"
    SOURCE1="$REPO_ROOT/terraform/credentials.auto.tfvars"
    SOURCE2="$REPO_ROOT/terraform/credentials.variables.tf"

    # Validate source exists
    [[ -f "$SOURCE1" ]] || echo "❌ Missing: $SOURCE1"
    [[ -f "$SOURCE2" ]] || echo "❌ Missing: $SOURCE2"

    # Compute RELATIVE path to source
    REL1=$(realpath --relative-to="$ENV_PATH" "$SOURCE1")
    REL2=$(realpath --relative-to="$ENV_PATH" "$SOURCE2")

    SYMLINK_MAP["$TARGET1"]="$REL1"
    SYMLINK_MAP["$TARGET2"]="$REL2"
  done
fi

# ---------- [🔁 DRY RUN REPORT] ----------
echo -e "${YELLOW}--- Symlink actions ---${RESET}"
for TARGET in "${!SYMLINK_MAP[@]}"; do
  SOURCE="${SYMLINK_MAP[$TARGET]}"
  echo -ne "${CYAN}🔗 $TARGET → $SOURCE${RESET} ... "

  if [ -f "$TARGET" ] && [ ! -L "$TARGET" ]; then
    echo -e "${RED}⚠️ File exists, not symlink${RESET}"
  elif [ -L "$TARGET" ] && [ ! -e "$TARGET" ]; then
    echo -e "${YELLOW}🔁 Broken symlink, will fix${RESET}"
  elif [ ! -e "$TARGET" ]; then
    echo -e "${GREEN}➕ Will create${RESET}"
  else
    echo -e "${GREEN}✔️ Already valid${RESET}"
  fi
done

# ---------- [🚀 APPLY CHANGES] ----------
echo
read -rp "$(echo -e "${BLUE}❓ Apply these changes now? [y/N]: ${RESET}")" CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  for TARGET in "${!SYMLINK_MAP[@]}"; do
    SOURCE="${SYMLINK_MAP[$TARGET]}"
    mkdir -p "$(dirname "$TARGET")"
    if [ -f "$TARGET" ] && [ ! -L "$TARGET" ]; then
      echo -e "${RED}⚠️ Skipping real file: $TARGET${RESET}"
    else
      rm -f "$TARGET"
      ln -s "$SOURCE" "$TARGET"
      echo -e "${GREEN}🔗 Linked: $TARGET → $SOURCE${RESET}"
    fi
  done
  echo -e "${GREEN}🎉 Done!${RESET}"
else
  echo -e "${YELLOW}⚠️ No changes were made.${RESET}"
fi
