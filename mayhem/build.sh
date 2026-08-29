#!/usr/bin/env bash
#
# mayhem/build.sh — stratagus (src/network/net_message.cpp, the multiplayer
# wire-format (de)serializer). Builds:
#   1) two libFuzzer harnesses (sanitized, DWARF-3):
#        /mayhem/netpacket_fuzz — CNetworkPacket::Deserialize (in-game UDP
#                                  command packets)
#        /mayhem/netinit_fuzz   — the CInitMessage_* pre-game handshake family
#   2) a standalone (non-fuzzer) run-once reproducer per harness
#   3) stratagus's own tests/network/test_network.cpp suite (doctest), with
#      NORMAL (unsanitized) flags — the functional-test oracle for test.sh.
#
# net_message.cpp is compiled and instrumented completely UNMODIFIED in every
# case above; only the harnesses and support shims under mayhem/ are ours.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

cd "$SRC"

INC="-I$SRC/src/include -I$SRC/src/include/network"

# --- 0) version-generated.h -------------------------------------------------
# Upstream generates this at CMake-configure time via tools/genversion.cpp
# (see CMakeLists.txt: add_custom_target(version-generated ...)). We run the
# same real upstream tool ourselves rather than hand-writing the header, so
# build.sh stays correct if the pinned major/minor/patch ever changes.
GENDIR="$SRC/mayhem-build/gen"
mkdir -p "$GENDIR"
$CXX -std=c++17 -O0 "$SRC/tools/genversion.cpp" -o "$GENDIR/genversion"
"$GENDIR/genversion" "$GENDIR/version-generated.h" "3.3.3.0"
INC="$INC -I$GENDIR"

# --- stage the harness/support sources (non-compiling .src extension so they
#     are never picked up as ordinary project files) into a scratch dir -----
STAGE="$SRC/mayhem-build/stage"
mkdir -p "$STAGE"
cp "$SRC/mayhem/netmsg_support.cpp.src"  "$STAGE/netmsg_support.cpp"
cp "$SRC/mayhem/netpacket_fuzz.cpp.src"  "$STAGE/netpacket_fuzz.cpp"
cp "$SRC/mayhem/netinit_fuzz.cpp.src"    "$STAGE/netinit_fuzz.cpp"
cp "$SRC/mayhem/lsan_off.cc"             "$STAGE/lsan_off.cc"

NET_MESSAGE_CPP="$SRC/src/network/net_message.cpp"

# --- 1) libFuzzer harnesses (sanitized) -------------------------------------
# net_message.cpp IS the library under test here (it's the whole fuzzed
# surface), so it's compiled straight into each harness binary with
# $SANITIZER_FLAGS — no separate "instrument the library" step is needed the
# way it would be for a harness that merely links against a prebuilt .a/.so.
for t in netpacket_fuzz netinit_fuzz; do
  $CXX -std=c++17 $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
      $INC \
      "$STAGE/${t}.cpp" "$STAGE/netmsg_support.cpp" "$STAGE/lsan_off.cc" "$NET_MESSAGE_CPP" \
      -o "/mayhem/${t}"
done

# --- 2) standalone (non-fuzzer) run-once reproducers ------------------------
# Compile the driver as C first so its LLVMFuzzerTestOneInput reference keeps
# C linkage (a C++ harness otherwise mangles the symbol).
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$SRC/mayhem-build/standalone_main.o"
for t in netpacket_fuzz netinit_fuzz; do
  $CXX -std=c++17 $SANITIZER_FLAGS $DEBUG_FLAGS \
      $INC \
      "$STAGE/${t}.cpp" "$STAGE/netmsg_support.cpp" "$STAGE/lsan_off.cc" "$NET_MESSAGE_CPP" \
      "$SRC/mayhem-build/standalone_main.o" \
      -o "/mayhem/${t}-standalone"
done

# --- 3) upstream functional test suite (doctest, NORMAL flags) -------------
# tests/network/test_network.cpp round-trips Serialize()/Deserialize() for
# every message class net_message.cpp defines against fixed, hand-chosen
# field values (FillCustomValue) and asserts byte-for-byte equality — the
# exact library our two harnesses fuzz. This build gets NEITHER the sanitizer
# NOR -gdwarf-3: it keeps the project's normal flags, which is what makes it
# an honest, independent oracle (see mayhem/test.sh).
cat > "$SRC/mayhem-build/test_main.cpp" <<'EOF'
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
EOF
$CXX -std=c++17 -g $INC -I/usr/include/doctest \
    "$SRC/mayhem-build/test_main.cpp" \
    "$SRC/tests/network/test_network.cpp" \
    "$STAGE/netmsg_support.cpp" "$NET_MESSAGE_CPP" \
    -o /mayhem/net_message_tests

echo "build.sh: OK"
