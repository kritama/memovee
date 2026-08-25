# OTP 29 exposes Ecto.Multi's internal MapSet representation as an opaque :sets value.
# See https://github.com/elixir-ecto/ecto/issues/4707.
[
  {"lib/memovee/memory/post/manager.ex", "Type mismatch in call without opaque term in update."},
  {"lib/memovee/memory/projection/manager.ex",
   "Type mismatch in call without opaque term in run."},
  {"lib/memovee/memory/projection/transitions.ex",
   "Type mismatch in call without opaque term in insert."}
]
