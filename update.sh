#!/bin/bash -ex
moon update && moon install && rm -rf target
moon fmt
# All targets except for 'js' and 'wasm-gc' currently fail: https://github.com/moonbitlang/core/issues/1219
# moon test --target native
# moon test --target all
moon test --target js
moon test --target wasm-gc
