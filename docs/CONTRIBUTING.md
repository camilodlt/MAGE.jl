# Maintaining the function galleries

Bundle docstrings describe the purpose, signatures, parameter sanitisation,
output conventions and limitations of each family. Operator registrations supply
a short `description` for the catalogue. Keep both descriptions faithful to the
kernel; names alone are not enough to establish what an operator does.

The home page discovers every exported `FunctionBundle` and groups it using
`BUNDLE_OUTPUT_GROUPS` in `bundle_inventory.jl`. Add an output group if a new
naming family is introduced; an unclassified bundle fails the documentation
build. The same file maps bundles to their detailed documentation pages. The
catalogue lists newly exported bundles even if their detailed page is not yet
assigned, and supplies stable anchors for the home-page links.

For an image operator, add an actual call and display its returned image. Use
`g_call(factory(OutputType), input, parameters...)`, or wrap a generated method
with `g_timed` and call it normally. Keep fixture loading, factory creation,
resizing for display, overlays and PNG encoding outside the call. Never replace
the displayed result with a simplified implementation of the operator.
`g_timed` is for deterministic examples that do not mutate inputs.

Use internal helpers when showing a representation the operator actually uses
(e.g. region bounds, Haar weights, orientation matrices). Explain units, sign,
coordinate conventions, clamping and any display normalisation. Show segment
labels with the shared palette, keeping background label zero black. Palette
colours cycle: equal colours do not prove labels equal when there are more
labels than palette entries. Display intensity outputs on their fixed `[0, 1]`
scale unless a caption explicitly explains another scale.

Name fixtures with `g_name!(image, "label")` before measuring them, so the
timing rows can be matched to the displayed inputs. For custom HTML layouts,
use `g_raw_gallery` from `gallery_paths.jl`; direct relative URLs in raw HTML
otherwise break when CI builds with directory URLs. When multiple volume
pages share an asset folder, give each page a distinct `volume_gallery_tag`
(or pass `asset_tag` to `g_volume_viewer`) so sprite counters cannot overwrite
another page's displayed data.

At the end of each gallery page, call `g_timings()` in every named example
sandbox used by that page. Its tables include each input combination and both
median and slowest observed warmed times. Add meaningful edge fixtures when
cost depends on structure or numeric parameters. Keep adversarial examples
small and explain how larger inputs scale; an observed maximum is not a
worst-case bound. See `src/timings.md` for the measurement contract.

The core gallery tracks the operator names it exercises and fails if a
registration in its covered bundles has no example. When adding an operator,
choose an input that reveals its effect and include useful parameter variants.

Prepare the docs environment with this checkout developed into it, then run:

```sh
nice -n 15 julia --project=docs docs/test/runtests.jl
nice -n 15 julia --project=docs docs/make.jl
```

The helper tests cover timing collection, output specialisations, label
rendering and bundle classification. The full Documenter build executes the
examples, resolves links, checks documented exports and enforces page size
limits. Inspect generated images and final HTML as well: a successful build
does not establish that a visual explanation is correct. Generated images live
under `docs/src/assets/fns` and `docs/build/assets/fns` and are ignored by Git.
