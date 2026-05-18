-module(timer_ffi).
-export([set_timeout/2]).

set_timeout(Ms, Callback) ->
  timer:apply_after(Ms, erlang, apply, [Callback, []]),
  nil.
