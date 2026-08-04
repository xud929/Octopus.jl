# Package extension activating the knob tree's Symbolics adapter
# (`knob_symbolic` / `knob_from_symbolic`) when the user loads Symbolics next
# to Octopus. This is the [weakdeps] fix for audit part 6's R3: a plain
# `import Symbolics` inside the module resolved only in script mode, so the
# adapter was permanently dead for every `using Octopus` -- while a runtime
# [deps] entry would contradict the project's choice to take no runtime
# dependency on an AD/symbolics package.
#
# The registration happens in `__init__`, not at top level: extension modules
# are precompiled, and a top-level call would mutate `_SYMBOLIC_ADAPTER`
# inside the precompile process and be discarded with it.
module OctopusSymbolicsExt

using Octopus
using Symbolics

__init__() = Octopus._activate_symbolics_adapter!(Symbolics)

end
