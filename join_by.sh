#!/usr/bin/env bash

# Joins arguments with first argument as separator
# I use it for associative arrays as `join_by , "${FOO[@]}"`
function join_by {
  local IFS="$1"
  shift
  echo -n "$*"
}
