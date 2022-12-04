openring:
	./openring.sh

serve: openring
	hugo serve -p 8080

build: openring
	hugo

build-prod: openring
	hugo --minify
