#!/bin/bash -ex
moon update && moon install && rm -rf target
moon fmt
# wasm-gc tests currently fail:
# moon test --target all
moon test --target js
