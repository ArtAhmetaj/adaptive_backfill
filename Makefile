.PHONY: help test format lint deps docs clean release

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

deps: ## Install dependencies
	mix deps.get

test: ## Run tests
	mix test

format: ## Format code
	mix format

format-check: ## Check code formatting
	mix format --check-formatted

lint: ## Run linter
	mix credo

check: format-check lint test ## Run all checks (format, lint, test)

docs: ## Generate documentation
	mix docs

clean: ## Clean build artifacts
	mix clean
	rm -rf _build deps doc

db-up: ## Start PostgreSQL with Docker
	docker-compose up -d

db-down: ## Stop PostgreSQL
	docker-compose down

db-logs: ## Show PostgreSQL logs
	docker-compose logs -f postgres

# Version management
bump-patch: ## Bump patch version (0.1.0 -> 0.1.1)
	@CURRENT=$$(grep 'version:' mix.exs | sed -n 's/.*version: "\(.*\)".*/\1/p' | head -1); \
	MAJOR=$$(echo $$CURRENT | cut -d. -f1); \
	MINOR=$$(echo $$CURRENT | cut -d. -f2); \
	PATCH=$$(echo $$CURRENT | cut -d. -f3); \
	NEW_PATCH=$$((PATCH + 1)); \
	NEW_VERSION="$$MAJOR.$$MINOR.$$NEW_PATCH"; \
	./scripts/bump_version.sh $$NEW_VERSION

bump-minor: ## Bump minor version (0.1.0 -> 0.2.0)
	@CURRENT=$$(grep 'version:' mix.exs | sed -n 's/.*version: "\(.*\)".*/\1/p' | head -1); \
	MAJOR=$$(echo $$CURRENT | cut -d. -f1); \
	MINOR=$$(echo $$CURRENT | cut -d. -f2); \
	NEW_MINOR=$$((MINOR + 1)); \
	NEW_VERSION="$$MAJOR.$$NEW_MINOR.0"; \
	./scripts/bump_version.sh $$NEW_VERSION

bump-major: ## Bump major version (0.1.0 -> 1.0.0)
	@CURRENT=$$(grep 'version:' mix.exs | sed -n 's/.*version: "\(.*\)".*/\1/p' | head -1); \
	MAJOR=$$(echo $$CURRENT | cut -d. -f1); \
	NEW_MAJOR=$$((MAJOR + 1)); \
	NEW_VERSION="$$NEW_MAJOR.0.0"; \
	./scripts/bump_version.sh $$NEW_VERSION

bump: ## Bump version (usage: make bump VERSION=0.2.0)
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make bump VERSION=0.2.0"; \
		exit 1; \
	fi
	./scripts/bump_version.sh $(VERSION)

release: check ## Create a release (runs checks, commits, tags, and pushes)
	@VERSION=$$(grep 'version:' mix.exs | sed -n 's/.*version: "\(.*\)".*/\1/p' | head -1); \
	echo "Creating release for version $$VERSION..."; \
	git add mix.exs CHANGELOG.md; \
	git commit -m "Release v$$VERSION"; \
	git tag "v$$VERSION"; \
	echo ""; \
	echo "✓ Release prepared!"; \
	echo ""; \
	echo "To publish, run:"; \
	echo "  git push origin main"; \
	echo "  git push origin v$$VERSION"

release-push: ## Push the release to trigger CI/CD
	@VERSION=$$(grep 'version:' mix.exs | sed -n 's/.*version: "\(.*\)".*/\1/p' | head -1); \
	git push origin main; \
	git push origin "v$$VERSION"; \
	echo ""; \
	echo "✓ Release v$$VERSION pushed!"; \
	echo "Check GitHub Actions for build status."
