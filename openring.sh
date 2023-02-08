#!/usr/bin/env bash

FEEDLIST=$1
INPUT_TEMPLATE=$2

readarray -t FEEDS < $FEEDLIST

# populated below
OPENRING_ARGS=""

for FEED in "${FEEDS[@]}"
do
   OPENRING_ARGS="$OPENRING_ARGS -s $FEED"
done

openring $OPENRING_ARGS < $INPUT_TEMPLATE
