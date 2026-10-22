# Run with the docs environment after developing this checkout into it:
#   nice -n 15 julia --project=docs docs/test/runtests.jl
using Test, MAGE
include(joinpath(@__DIR__, "..", "gallery_helpers.jl"))
include(joinpath(@__DIR__, "..", "bundle_inventory.jl"))

@testset "Gallery measurements" begin
    empty!(G_TIMINGS); empty!(G_TIMING_KEYS); empty!(G_INPUT_IDS)
    withenv("MAGE_DOC_TIMING_SAMPLES" => "2") do
        calls = Ref(0)
        counted(x) = (calls[] += 1; (x, calls[]))
        # The displayed value is the first call's actual output.
        @test g_call(counted, 7) == (7, 1)
        @test calls[] == 3
        @test length(G_TIMINGS) == 1
        @test G_TIMINGS[1].samples == 2
        @test G_TIMINGS[1].median <= G_TIMINGS[1].maximum
        @test g_call(counted, 7) == (7, 4)
        @test calls[] == 4                    # identical case is not sampled twice
        @test g_timed(g_timed(identity))(9) == 9
        @test g_call(g_timed(identity), 9) == 9
        # An intensity and binary output from the same input need separate rows.
        input = g_intensity([0.0 0.3; 0.8 1.0])
        @test g_name!(input, "test fixture") === input
        @test occursin("test fixture", g_argument(input))
        I = typeof(input)
        B = typeof(g_binary(falses(2, 2)))
        before = length(G_TIMINGS)
        for (bundle, T) in ((bundle_image2DIntensity_filtering_factory, I),
                            (bundle_image2DBinary_filtering_factory, B))
            fn = bundle[:sobelm_image2D].fn(T)
            @test g_call(fn, input) isa T
        end
        @test length(G_TIMINGS) == before + 2
        @test G_TIMINGS[end].output != G_TIMINGS[end-1].output
        @test G_TIMINGS[end].name == "sobelm_image2D"
        g_call(abs, -1.0)
        g_call(abs, -2.0)
        html = sprint(show, MIME"text/html"(), g_timings())
        @test g_scalar_ranges(filter(t -> t.name == "abs", G_TIMINGS)) == "arg1: [-2.0, -1.0]"
        @test length(collect(eachmatch(r"<code>abs</code>", html))) == 1
        @test occursin("Observed max", sprint(show, MIME"text/html"(), g_timings()))
    end
end

@testset "Segmentation gallery rendering" begin
    pixels = SegmentPixel{Int}.([0 1; 2 3])
    @test g_slice_canvas(pixels) == g_canvas(SImageND(pixels))
    @test length(unique(g_slice_canvas(pixels))) == 4
    @test g_slice_canvas(pixels)[1, 1] == G_PALETTE[1]
end

@testset "Every exported bundle has one output group" begin
    names_ = exported_bundles()
    @test !isempty(names_)
    for name in names_
        @test count(pair -> occursin(last(pair), name), BUNDLE_OUTPUT_GROUPS) == 1
    end
    html = sprint(show, MIME"text/html"(), bundle_output_index())
    for name in names_
        @test occursin(name, html)
    end
end

@testset "Home-page links have stable catalogue targets" begin
    for name in (first(exported_bundles()), last(exported_bundles()))
        html = bundle_catalogue_html("`MAGEBUNDLEANCHOR$name`\n\n### `$name`\n")
        @test occursin("id=\"$name\"", html)
        @test !occursin("MAGEBUNDLEANCHOR", html)
    end
    withenv("CI" => "true") do
        html = sprint(show, MIME"text/html"(), bundle_output_index())
        @test occursin("libraries/catalogue/#", html)
    end
end


@testset "Gallery paths in local and CI builds" begin
    for (ci, library_prefix, root_prefix) in (("false", "../assets/fns", "assets/fns"),
                                             ("true", "../../assets/fns", "../assets/fns"))
        withenv("CI" => ci) do
            @test g_asset_prefix() == library_prefix
            @test g_asset_prefix(library_page = false) == root_prefix
            html = g_raw_gallery("<img src=\"../assets/fns/demo/input.png\">")
            @test occursin(library_prefix * "/demo/input.png", sprint(show, MIME"text/html"(), html))
        end
    end
end


@testset "Independent volume viewers do not overwrite sprites" begin
    first_scope, second_scope = Module(:same_name), Module(:same_name)
    @test nameof(first_scope) == nameof(second_scope)
    Base.include(first_scope, joinpath(@__DIR__, "..", "gallery_paths.jl"))
    Base.include(second_scope, joinpath(@__DIR__, "..", "gallery_paths.jl"))
    @test Base.invokelatest(getfield(first_scope, :g_viewer_tag)) !=
          Base.invokelatest(getfield(second_scope, :g_viewer_tag))
    directory = mktempdir()
    saved_counter = G_VIEWER_COUNT[]
    try
        volume = g_intensity(zeros(2, 3, 4))
        G_VIEWER_COUNT[] = 0
        first_view = g_volume_viewer(["first" => volume]; scale = 1,
            assets = [directory], page = "shared", asset_tag = "first_page")
        first_files = Set(readdir(directory))
        @test length(first_files) == 3
        G_VIEWER_COUNT[] = 0 # a second page starts its own counter at zero
        second_view = g_volume_viewer(["second" => volume]; scale = 1,
            assets = [directory], page = "shared", asset_tag = "second_page")
        second_files = setdiff(Set(readdir(directory)), first_files)
        @test length(second_files) == 3
        @test all(startswith("first_page_"), first_files)
        @test all(startswith("second_page_"), second_files)
        @test occursin("first_page_vv1", sprint(show, MIME"text/html"(), first_view))
        @test occursin("second_page_vv1", sprint(show, MIME"text/html"(), second_view))
    finally
        G_VIEWER_COUNT[] = saved_counter
        rm(directory; recursive = true)
    end
end


@testset "Generated region headings have navigation anchors" begin
    html = g_operator_anchors("<h3><code>region_mean_5p</code></h3>")
    @test occursin("id=\"region_mean_5p\"", html)
end
