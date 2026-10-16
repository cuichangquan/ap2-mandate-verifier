# STATIC DESIGN ONLY. Do not build/pull under this approval.
# Final target: linux/amd64 Ruby3.3.12 slim-bookworm, pinned amd64 manifest:
# sha256:64788045fc5e88016aa060f91b5b25cc0c41aed52accc7625cfca48037b0ec35
# Index sha256:2e32876dfe84913ec84eb4a59617f72dab7c0989d38f8219487491e384543975
#
# No FROM ruby / remote frontend: even an accidental build of this static
# marker must not retrieve an image or imply an assembled runtime exists.
FROM scratch
LABEL org.ap2.research.status="STATIC_ONLY_NO_RUNTIME"
COPY research/phase2a_e06i/p1r_input_contract.json /STATIC_ONLY_INPUT_CONTRACT.json
# The absent executable prevents this marker image from running a program.
ENTRYPOINT ["/STATIC_ONLY_NO_EXECUTABLE"]
#
# Future separately approved recipe (NOT implemented by this marker):
# 1. Bounded fetch, size/hash/signature/expiry verify all frozen inputs.
# 2. Offline load verified OCI layers; reconcile OS/Python/Git dependencies.
# 3. Offline fixed .deb, pip bootstrap wheel,16 wheels,5 gems and any
#    independently frozen default/native closure. No resolver/sdist/compiler.
# 4. Freeze expected source/runtime/load-path inventory; immutable image.
# 5. Nonroot, read-only root/source, network/DNS none, cap-drop ALL,
#    no-new-privileges, bounded scratch/cgroup watchdog established outside.
# Missing Git/pip/ABI/source inventory or bootstrap trust means STOP.
