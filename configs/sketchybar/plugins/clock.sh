#!/usr/bin/env bash
# Periodic clock updater. Wired in sketchybarrc as a right-anchored
# item with update_freq=20; HH:MM granularity makes 20s ample.
sketchybar --set "$NAME" label="$(date +"%H:%M")"
