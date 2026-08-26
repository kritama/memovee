# OTP 28+ exposes Ecto.Multi's internal MapSet representation as an opaque :sets value.
# See https://github.com/elixir-ecto/ecto/issues/4707.
#
# Dialyxir applies regex filters to its short output. Filtering the warning type globally keeps
# this workaround independent of each Ecto.Multi call site while retaining other opaque warnings.
[
  ~r/:call_without_opaque Type mismatch in call without opaque term in/
]
