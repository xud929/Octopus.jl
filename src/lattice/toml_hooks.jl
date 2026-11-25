# The snapshot codec for the objects a line holds beside its elements (design
# D6 and D13): in-line hooks (`ScheduledObserver`, `ScheduledAction`), the
# collision markers with their solvers, the schedules, the solvers' nested
# option objects, and the turn rules. Included after the tasks, whose types
# these methods name; the codec's dispatch points and the element rules live
# in src/lattice/toml.jl.
#
# STUBS (unit B), each documented when filled, each registered in `_TOML_OBJECT_TYPES`:
#   _toml_encode_object(x::ScheduledObserver, ctx)     observer + schedule tables
#   _toml_encode_object(x::ScheduledAction, ctx)       refused by name when the action holds a function (BeamSwapAction); else its options
#   _toml_encode_object(x::StrongStrongCollision, ctx) label + poisson_solver (nothing allowed)
#   _toml_encode_object(x::AbstractPoissonSolver, ctx) solver_option_schema keys, requested values, nested objects recursively
#   _toml_encode_object(x::AbstractSchedule, ctx)      schedule_option_schema; PredicateSchedule refused by name
#   _toml_encode_object(x::AbstractBeamObserver, ctx)  observer_option_schema (MomentObserver: a faithful rebuild of its resolved moments)
#   _toml_encode_object(x::LongitudinalSlicing, ctx), virtual drift objects, CUDAPICLaunchConfig
#   _toml_encode_object(x::WhiteNoise | PinkNoise, ctx) fields; TurnTable -> the sidecar by digest; SpectralNoise refused by name
#   the matching `_toml_decode_object` methods (by type name through `_TOML_OBJECT_TYPES`, keyword constructors)
#   `_toml_refused_object_types()` -> the documented refusal list the suite's tripwire reads
