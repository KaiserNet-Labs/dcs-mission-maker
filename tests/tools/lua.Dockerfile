# Lua 5.1 for the syntax test of the DCS hook and the dumped mission Lua (.workbench/settings.json, release.tests).
# Built on the Box from the commit by the Workbench's build and trial-tests; the test itself runs with no network.
FROM debian:stable-slim@sha256:fbfb4059d2127120aa05b6e6064523d2102552f0cf0026ddf0701c12f1f8f3e0
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends lua5.1 \
 && rm -rf /var/lib/apt/lists/*
USER 65534
