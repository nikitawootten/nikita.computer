SHELL := /bin/bash

openring_output := layouts/partials/openring.html
openring_feeds := config/openring/feeds.txt
openring_template := config/openring/openring_template.html

.PHONY: serve
serve: $(openring_output)
	hugo serve -p 8080

.PHONY: build
build: $(openring_output)
	hugo

.PHONY: build-prod
build-prod: $(openring_output)
	hugo --minify

$(openring_output): $(openring_feeds) $(openring_template)
	./openring.sh $(openring_feeds) $(openring_template) > $(openring_output)

.PHONY: clean
clean:
	rm $(openring_output)
	rm -fr public
