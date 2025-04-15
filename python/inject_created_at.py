#!/usr/bin/env python3
import os
import sys
import json
import requests
from pathlib import Path
from dotenv import load_dotenv

# 📦 Load .env if Vault env vars are missing
if "VAULT_ADDR" not in os.environ or "VAULT_TOKEN" not in os.environ:
    dotenv_path = Path(__file__).resolve().parents[1] / ".env"
    if dotenv_path.exists():
        load_dotenv(dotenv_path)
    else:
        sys.exit("❌ .env file missing and Vault env vars not set")

VAULT_ADDR = os.getenv("VAULT_ADDR")
VAULT_TOKEN = os.getenv("VAULT_TOKEN")

if not VAULT_ADDR or not VAULT_TOKEN:
    sys.exit(
        "❌ Vault not authenticated. Set VAULT_ADDR and VAULT_TOKEN or provide .env."
    )

HEADERS = {"X-Vault-Token": VAULT_TOKEN, "Content-Type": "application/json"}


def get_secret(path):
    """📥 Fetch a secret value from Vault"""
    url = f"{VAULT_ADDR}/v1/{path}"
    r = requests.get(url, headers=HEADERS)
    if r.status_code == 200:
        return r.json()["data"]["data"]["value"]
    else:
        sys.exit(
            f"❌ Failed to load secret from Vault: {path} ({r.status_code}) {r.text}"
        )


def load_tfvars_content(path):
    with open(path, "r") as f:
        return f.read()


def push_to_vault(env_name, content):
    """🔐 Push updated tfvars to Vault"""
    payload = {"data": {"value": content}}
    url = f"{VAULT_ADDR}/v1/kv/data/home-ops/opentofu/homelab/{env_name}/terraform-auto-tfvars"

    r = requests.put(url, headers=HEADERS, data=json.dumps(payload))
    if r.status_code not in [200, 204]:
        sys.exit(f"❌ Vault push failed ({r.status_code}): {r.text}")


def trigger_github_dispatch(event_type):
    """🚀 Fire GitHub Actions workflow_dispatch via repo API"""
    GITHUB_PAT = get_secret("kv/data/home-ops/github/webhook-token")

    repo = "mineblow/home-ops"
    url = f"https://api.github.com/repos/{repo}/dispatches"
    payload = {"event_type": event_type}

    headers = {
        "Authorization": f"token {GITHUB_PAT}",
        "Accept": "application/vnd.github.everest-preview+json",
    }

    r = requests.post(url, headers=headers, data=json.dumps(payload))
    if r.status_code != 204:
        sys.exit(f"❌ GitHub webhook failed ({r.status_code}): {r.text}")
    else:
        print(f"✅ GitHub workflow dispatched: {event_type}")


def tfvars_changed(path, content):
    """🔍 Detect if local file content differs from what's in Vault"""
    env_name = Path(path).parent.name
    vault_url = f"{VAULT_ADDR}/v1/kv/data/home-ops/opentofu/homelab/{env_name}/terraform-auto-tfvars"

    r = requests.get(vault_url, headers=HEADERS)
    if r.status_code == 200:
        current = r.json()["data"]["data"]["value"]
        return content.strip() != current.strip()
    elif r.status_code == 404:
        return True  # No file yet
    else:
        sys.exit(f"❌ Vault read failed ({r.status_code}): {r.text}")


def main():
    if len(sys.argv) < 2:
        root = Path("terraform/environments")
        tfvars_files = list(root.rglob("terraform.auto.tfvars"))
        if not tfvars_files:
            sys.exit("❌ No terraform.auto.tfvars files found")
    else:
        tfvars_files = [Path(p) for p in sys.argv[1:]]

    updated_envs = []

    for path in tfvars_files:
        content = load_tfvars_content(path)
        if tfvars_changed(path, content):
            env_name = path.parent.name
            print(f"📤 Updating Vault: {env_name}")
            push_to_vault(env_name, content)
            updated_envs.append(env_name)

    if updated_envs:
        for env in updated_envs:
            if env == "bootstrap-runner":
                trigger_github_dispatch("terraform-bootstrap-runner")
            else:
                trigger_github_dispatch("terraform-auto-matrix")


if __name__ == "__main__":
    main()
