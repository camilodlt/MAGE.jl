# Library edits are generation-boundary operations, never concurrent with decode.
# The atomic stamp allows independent tables/tasks to observe invalidation safely.
const _decode_library_version = Threads.Atomic{UInt}(0)
library_decode_version() = _decode_library_version[]
"""Invalidate shared decoding metadata after direct library/method edits.
Call at a quiescent boundary (no concurrent decode or library mutation).
Repository library mutators call this automatically.
"""
bump_library_decode_version!() = Threads.atomic_add!(_decode_library_version, UInt(1)) + UInt(1)
