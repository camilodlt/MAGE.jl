# Changelog

Changes are recorded here as they are made. Unreleased changes move to a dated
version section when a release is tagged. The recent history below starts with
the October 2026 updates; it is not a complete record of earlier development.

## Unreleased

### Breaking changes

- Rename the Julia package and module to `MAGE`, with entry point `src/MAGE.jl`.
  Update imports, qualified references and dependency keys to `MAGE`. The package
  UUID remains `956831e1-0a7a-492a-ae16-058c6128a9f2`.
- Rename configuration variables to the `MAGE_` prefix. See the configuration
  manual for supported variables and defaults.
- Update extensions, generated-code references, examples and tests to the new
  module name. Rebuild sysimages and regenerate saved Julia source. Serialized
  objects referring to the previous module name may require their original
  environment for loading and export. Dependent packages and runner projects
  must update their imports and dependency keys too.

### Added

- This changelog, including migration guidance for the package rename.
- Regression checks for package identity and `MAGE_` environment configuration.

## Recent development before the rename

These entries identify development commits, not published releases.

### 2026-10-20

- Add Julia 1.13 to CI and use it for documentation builds, retaining coverage
  for Julia 1.11.7 and 1.12. Add compatibility badges and recommend Julia 1.13.
  ([26c3fe6](https://github.com/camilodlt/MAGE.jl/commit/26c3fe6))
- Improve documentation coverage, gallery timing labels and image-reference
  organisation. Fix parallel evaluator workspace indexing when an interactive
  thread pool is present, and update factory tests for Julia's world-age rules.
  ([d0e301d](https://github.com/camilodlt/MAGE.jl/commit/d0e301d))
- Keep max-flow budget exhaustion, evaluator recovery and normal-cut correctness
  checks; remove the hardware-dependent three-second assertion from CI.
  ([a82a5a1](https://github.com/camilodlt/MAGE.jl/commit/a82a5a1))

### 2026-10-19

- Fix neutral local contrast for constant RGB inputs and Julia 1.12 compatibility.
  ([e1add09](https://github.com/camilodlt/MAGE.jl/commit/e1add09))
- Give generated factories stable names for sysimage reuse and serialize their
  definitions to protect concurrent factory construction.
  ([0d9b8a9](https://github.com/camilodlt/MAGE.jl/commit/0d9b8a9),
  [bd0b2a3](https://github.com/camilodlt/MAGE.jl/commit/bd0b2a3))

### 2026-10-18

- Bound segmentation work using a 32-pixel working grid and a max-flow operation
  budget that grows linearly with graph size above a fixed minimum allowance.
  ([ec7f365](https://github.com/camilodlt/MAGE.jl/commit/ec7f365))

### 2026-10-17

- Improve image and RGB operators with direct writes into output buffers, cached
  kernels and an `N0f8` gamma lookup table.
  ([823f3cc](https://github.com/camilodlt/MAGE.jl/commit/823f3cc),
  [eeca3dd](https://github.com/camilodlt/MAGE.jl/commit/eeca3dd))

### 2026-10-16

- Add the typed population evaluator with tiled and per-sample engines and a
  buffer pool, alongside image-library, ADF and documentation updates.
  ([19a4fa5](https://github.com/camilodlt/MAGE.jl/commit/19a4fa5))
