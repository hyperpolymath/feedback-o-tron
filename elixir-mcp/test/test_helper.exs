# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# Tests tagged :escript need a built binary (mix escript.build); run them
# with `mix test --only escript`.
ExUnit.start(exclude: [:escript])
