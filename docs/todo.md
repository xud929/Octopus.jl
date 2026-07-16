# TODO

## Task Diagnostics API

Move runtime diagnostic controls into explicit task configuration.

Current state:

- Some diagnostics are controlled by environment variables read inside runtime
  code, for example `OCTOPUS_CUDA_MEMORY_LOG_EVERY`.
- This is convenient for shell and batch runs, but hidden from constructors,
  docstrings, notebooks, and API discovery.

Target design:

- Define diagnostics as task-level options, for example
  `StrongStrongTask(...; memory_log_every=100)`.
- Keep environment variables only in examples as command-line convenience
  adapters.
- Examples should parse environment variables and pass explicit task options.
- Runtime code should prefer task fields over direct `ENV` reads.

This keeps the public API discoverable while preserving convenient command-line
usage for long tracking runs.
