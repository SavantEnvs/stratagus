# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) for stratagus — builds on top of the
# org C/C++ base image (ghcr.io/savantenvs/base), which already provides
# debian + clang/llvm + libFuzzer + the mayhem identities + the build-contract
# ENV (SRC, SANITIZER_FLAGS, LIB_FUZZING_ENGINE, STANDALONE_FUZZ_MAIN).
#
# What gets fuzzed: src/network/net_message.cpp — Stratagus's wire-format
# (de)serializer for multiplayer network messages (both the in-game UDP
# command packets and the pre-game connection handshake). It is compiled and
# instrumented completely unmodified; see mayhem/build.sh and
# mayhem/*_fuzz.cpp.src for the harnesses.
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t mytag .

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); do NOT bake it as an
# ENV — an empty value breaks clang both here and for any in-image rebuild.
# build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH

# Sanitizer override: the base exports SANITIZER_FLAGS (ASan+UBSan, halting)
# as the default. Declared WITHOUT a default (no '=') so the base ENV flows
# through when not passed, and an explicit --build-arg overrides it.
ARG SANITIZER_FLAGS
# Build parallelism (optional); build.sh falls back to nproc when unset.
ARG MAYHEM_JOBS=

# net_message.cpp/net_message.h are otherwise self-contained (no SDL, no Lua,
# no rendering/audio) — the ONLY extra package needed is doctest, to build and
# run stratagus's own tests/network/test_network.cpp as the functional-test
# oracle (mayhem/test.sh). Re-pin the apt sources list to SOURCE_DATE_EPOCH
# first for reproducibility (repro-sources-list.sh ships in the base).
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends doctest-dev \
 && rm -rf /var/lib/apt/lists/*
USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl.
# .git history) is copied to /mayhem as `mayhem`; build.sh builds in place.
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

# Run stratagus's own tests/network/test_network.cpp suite (built by
# build.sh) at image-build time. A failing suite fails the image build.
RUN bash mayhem/test.sh

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
