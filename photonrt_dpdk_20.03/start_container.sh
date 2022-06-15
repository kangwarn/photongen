#!/bin/bash
# docker run -d -v $(pwd)/diff:/root/diff photon3-rt-kc:latest bash -c "while true; do sleep 3600; done"
docker run -d --privileged photon_dpdk20.11:v1 bash -c "while true; do sleep 3600; done"
