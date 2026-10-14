#!/usr/bin/env bash
# E06-I A10-S preparation source — APPROVED FOR STATIC REVIEW ONLY.
# Issue #73 / Issue #101. NOT Approval P1 or B.
# This file deliberately has NO download, package-install, OCI build,
# Docker invocation, fixture generation, test, network, CI or report upload.
# No operator-controlled environment variable/CLI flag may unlock it.
#
# Safety proposition:
# Missing externally reviewed complete dependency SHA256 closure or a
# verified final OCI digest MUST NOT silently turn into a mutable tag,
# private registry, live resolver, self-generated digest or successful run.
#
# The intended one-time future preparation P1 is a DIFFERENT authority.
# Any transition from this STOP-only source to executable preparation
# requires a separately reviewed change and explicit Owner permission.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C

readonly A10_PHASE='SOURCE_ONLY_HOLD'
readonly A10_VERIFIER_MAIN='cd72c07947c2f6dfbc1ef900de252e7b82b74712'
readonly A10_OFFICIAL_AP2='b4587ac1d055888a73b4b21750973cffba961793'
readonly A10_LINUX_PLATFORM='linux/amd64'
readonly A10_RUBY_TARGET='3.3'
readonly A10_PYTHON_MIN='3.11'
readonly A10_JWT_GEM='3.3.0'
readonly A10_JSON_SCHEMER_GEM='2.5.0'
readonly A10_IP_CASES='IP01,IP02,IP03'

# Dependency pins below are REQUIRED but have NOT yet been independently
# validated, therefore remain intentionally unset. Do NOT substitute the
# candidate public Docker Hub base digest for the reviewed final OCI digest.
readonly A10_VERIFIED_BASE_OCI_DIGEST='UNSET'
readonly A10_VERIFIED_FINAL_OCI_DIGEST='UNSET'
readonly A10_TRUSTED_PYTHON_FULL_WHEELHOUSE_SHA256='UNSET'
readonly A10_TRUSTED_RUBY_FULL_GEM_CLOSURE_SHA256='UNSET'
readonly A10_TRUSTED_OS_NATIVE_LOADER_CLOSURE_SHA256='UNSET'
readonly A10_TRUSTED_AP2_SOURCE_AND_SCHEMAS_SHA256='UNSET'
readonly A10_TRUSTED_SUPERVISOR_SOURCE_SHA256='UNSET'

# Preparation P1 design contract only, not executable instructions:
#
# 0. Explicit Owner P1 approval must separately identify one preparation
#    run, standard ubuntu-24.04 host, <=10 min, zero additional billing,
#    no automatic triggers or reruns. Storage/billing unknown => STOP.
# 1. A separately reviewed control plane must establish exact expected
#    source/artifact hashes BEFORE package download/build or interpreter
#    import. Git HEAD from the candidate worktree, a mutable file or
#    caller-provided checksum list is NOT an independent trust anchor.
# 2. Pin OCI base by registry, sha256 digest and linux/amd64 manifest
#    (not a rolling :tag; distinguish multiarch index from leaf manifest).
#    Pin Debian package sources / build frontend / runtime image OS closure.
# 3. Pin ALL direct/transitive platform-specific Python wheel versions
#    and wheel SHA256 hashes. Never use private AP2 uv.lock staging registry
#    as an implicit authenticated installer; prohibit unpinned sdist and
#    package installers with live resolver fallback. Future installation
#    should be offline from independently verified wheels.
# 4. Pin ALL direct/transitive .gem artifact SHA256 values: jwt 3.3.0,
#    json_schemer 2.5.0, bigdecimal, hana, regexp_parser, simpleidn,
#    default/native gems and search paths. Check actual resolved imports,
#    shared objects, Ruby/Python runtimes, libcrypto and dynamic loader.
# 5. Independently pin verifier source, AP2 exact commit, 3 local official
#    JSON Schemas, A8/A9 Ruby/Python original-signature research sources.
# 6. Preparation only: ONE bounded OCI candidate, never push/tag publicly,
#    upload artifact/cache/package, expose secret, generate signed fixtures,
#    run Verifier or an O1–O5 oracle. Ephemeral CI images are not persistently
#    available for the later B experiment by virtue of having been built.
# 7. Independently record reviewed inputs, content identities, OS image
#    build/source attestation and final OCI digest. Self-hash is NOT proof of
#    source authenticity or run-time immutability. Missing or inconsistent
#    input, registry, ABI/import closure, OS lifetime or cleanup => STOP.
#
# A10-S source cannot claim any of the above as proven. Future P1
# preparation and future B signed pilot require SEPARATE Owner approvals;
# the disabled workflow may not be enabled under A10-S.

printf '%s\n' \
  'E06-I A10-S: HOLD / PREPARATION_NOT_AUTHORIZED' \
  'Dependency/SHA256 closure, trusted OCI digest and external supervisor not established.' \
  'No build, package install, fixture, test or network operation is permitted.' >&2
exit 78
