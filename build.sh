#!/bin/bash
rm -rf build
mkdir build
pushd build
xgo --targets=linux/amd64,linux/arm-7,linux/386 github.com/immesys/bwadvisor
popd
