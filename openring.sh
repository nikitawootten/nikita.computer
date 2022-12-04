#!/usr/bin/env bash

FEEDLIST=config/openring/feeds.txt
INPUT_TEMPLATE=config/openring/openring_template.html
OUTPUT=layouts/partials/openring.html

readarray -t FEEDS < $FEEDLIST

# populated below
OPENRING_ARGS=""

for FEED in "${FEEDS[@]}"
do
   OPENRING_ARGS="$OPENRING_ARGS -s $FEED"
done

openring $OPENRING_ARGS < $INPUT_TEMPLATE > $OUTPUT
