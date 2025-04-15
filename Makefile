# Makefile for home-ops

.PHONY: all bootstrap plan apply inject-created-at lint clean check-env ensure-tools

# === [🌍 PATH Check] ===
ifeq (,$(findstring $(HOME)/.local/bin,$(PATH)))
$(warning ⚠️  ~/.local/bin is not in your PATH — binaries like 'pre-commit' may not work!)
$(warning 💡 Run: echo 'export PATH="$$HOME/.local/bin:$$PATH"' >> ~/.bashrc && source ~/.bashrc)
endif

# 🚀 Quickstart setup
bootstrap:
	pipx install pre-commit || true
	~/.local/bin/pre-commit install
	~/.local/bin/pre-commit install --hook-type commit-msg
	~/.local/bin/pre-commit autoupdate

# 🧠 Run your timestamp injector manually
inject-created-at:
	python3 python/inject_created_at.py terraform/environments/homelab/bootstrap-runner/terraform.auto.tfvars

# 🖌️ Run full pre-commit checks manually
lint:
	~/.local/bin/pre-commit run --all-files

# 📊 Terraform plan wrapper
plan:
	cd terraform/environments/homelab/bootstrap-runner && tofu init -reconfigure && tofu plan

# 🚑 Terraform apply wrapper
apply:
	cd terraform/environments/homelab/bootstrap-runner && tofu apply

# 🗑️ Clean generated files
clean:
	rm -f terraform/environments/homelab/bootstrap-runner/terraform.auto.tfvars.bak
	rm -f terraform/environments/homelab/bootstrap-runner/backend-consul.hcl
	rm -f tfplan

# ✅ Validate dev environment tools are installed
check-env:
	@command -v python3 >/dev/null || (echo "❌ Missing python3" && exit 1)
	@command -v pipx >/dev/null || (echo "❌ Missing pipx" && exit 1)
	@command -v vault >/dev/null || (echo "❌ Missing vault CLI" && exit 1)
	@command -v make >/dev/null || (echo "❌ Missing make" && exit 1)
	@echo "✅ Dev environment OK"


ensure-tools:
	@echo "🔧 Ensuring Python tools are ready..."
	pipx install pre-commit || true
	pipx inject pre-commit python-hcl2 || true
	@echo "✅ Running: pre-commit install"
	$(HOME)/.local/bin/pre-commit install
