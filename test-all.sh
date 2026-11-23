#!/bin/bash -ex
moon fmt && moon info
moon test --deny-warn
# moon test --target all
