SHELL := /usr/bin/env bash

openring_output := layouts/partials/openring.html
openring_feeds := config/openring/feeds.txt
openring_template := config/openring/openring_template.html

.PHONY: help
# This help command was adapted from https://github.com/tiiuae/sbomnix
# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?##.*$$' $(MAKEFILE_LIST) | awk 'BEGIN { \
	  FS = ":.*?## "; \
	  printf "\033[1m%-30s\033[0m %s\n", "TARGET", "DESCRIPTION" \
	} \
	{ printf "\033[32m%-30s\033[0m %s\n", $$1, $$2 }'

.PHONY: serve
serve: $(openring_output) ## Preview the site on port 8080
	hugo serve -p 8080

.PHONY: build
build: $(openring_output) ## Build the site (output in "public")
	hugo

.PHONY: build-prod
build-prod: $(openring_output) ## Build the minified site
	hugo --minify

$(openring_output): $(openring_feeds) $(openring_template)
	./openring.sh $(openring_feeds) $(openring_template) > $(openring_output)

.PHONY: clean
clean: ## Clear the Hugo build and Openring output
	rm $(openring_output)
	rm -fr public
