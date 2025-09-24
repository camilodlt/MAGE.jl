""" Image To Graph

Exports :

- **bundle\\_float\\_imagegraph** :
    - `identity_float`

"""
module imagegraph_basic

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImage2D, SImageND
using ImageCore: float64
using FixedPointNumbers: Normed
using StatsBase: countmap
using Statistics: mean, median, std
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ..UTCGP:
    SizedImage, SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, _get_image_pixel_type,
    IntensityPixel, BinaryPixel, SegmentPixel

using Images, ImageSegmentation, Statistics
# using ImageView
using ImageSegmentation, Statistics
using DelaunayTriangulation
using Graphs
using Random
using DispatchDoctor
# using GraphPlot, Colors

function make_graph_from_binary_img(img)
    labelized = label_components(img)
    labels = unique(labelized)

    if length(labels) <= 2
        throw(DimensionMismatch("Only two centers for triangulation"))
    end

    centroids = Dict()
    centroids_mapping = Dict()
    for (i, label) in enumerate(labels)
        # Find all pixels with this label
        indices = findall(labelized .== label)
        # Convert to row, column coordinates
        coords = [(ind[1], ind[2]) for ind in indices]
        # Calculate centroid
        y_coords = [c[1] for c in coords]
        x_coords = [c[2] for c in coords]
        centroids[label] = (mean(y_coords), mean(x_coords))
        centroids_mapping[i] = label
    end
    cell_centers = collect(values(centroids))
    n_cells = length(cell_centers)
    points = [(Float64(p[1]), Float64(p[2])) for p in cell_centers]
    t = @elapsed tri = triangulate(points; rng = Xoshiro(0), predicates = DelaunayTriangulation.FastKernel())
    if n_cells > 100
        @warn "A lot of points $n_cells : time $t"

        if isdefined(Main, :Infiltrator)
            Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        end
    end

    # Extract edges from triangulation to create a graph
    edges = Set{Tuple{Int, Int}}()
    for triangle in get_triangles(tri)
        push!(edges, (triangle[1], triangle[2]))
        push!(edges, (triangle[2], triangle[3]))
        push!(edges, (triangle[3], triangle[1]))
    end

    # Create graph from edges
    g = SimpleGraph(n_cells)
    for (i, j) in edges
        Graphs.add_edge!(g, i, j)
    end

    if isdefined(Main, :Infiltrator)
        Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    end
    return g, centroids, centroids_mapping, cell_centers, labelized
end


fallback(args...) = return 0.0

bundle_float_imagegraph = FunctionBundle(fallback)

# ##################### #
# BETWEENESS CENTRALITY #
# ##################### #

fns = [
    betweenness_centrality,
    closeness_centrality,
    degree_centrality,
    indegree_centrality,
    outdegree_centrality,
    eigenvector_centrality,
    radiality_centrality,
    stress_centrality,
    local_clustering_coefficient,
    triangles,
    eccentricity,
]
for metric in fns
    for (stat_name, stat) in zip(
            ["mean", "median", "minimum", "maximum", "std"],
            [mean, median, minimum, maximum, std]
        )
        name = Symbol("$(stat_name)$(metric)_float_factory")
        @show name
        @eval @stable function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
            t = @elapsed g, centroids, centroids_mapping, centers, labelized = make_graph_from_binary_img(img)
            t2 = @elapsed res = $metric(g) |> $(stat)
            return res
        end
    end

    name = Symbol("xCoorArgmax$(metric)_float_factory")
    @show name
    @eval @stable function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
        t = @elapsed g, centroids, centroids_mapping, centers, labelized = make_graph_from_binary_img(img)
        t2 = @elapsed which = $metric(g) |> argmax
        res = centers[which][1]
        return res
    end

    name = Symbol("yCoorArgmax$(metric)_float_factory")
    @show name
    @eval @stable function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
        t = @elapsed g, centroids, centroids_mapping, centers, labelized = make_graph_from_binary_img(img)
        t2 = @elapsed which = $metric(g) |> argmax
        return centers[which][2]
    end

    name = Symbol("xCoorArgmin$(metric)_float_factory")
    @show name
    @eval @stable function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
        t = @elapsed g, centroids, centroids_mapping, centers, labelized = make_graph_from_binary_img(img)
        t2 = @elapsed which = $metric(g) |> argmin
        res = centers[which][1]
        return res
    end

    name = Symbol("yCoorArgmin$(metric)_float_factory")
    @show name
    @eval @stable function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
        t = @elapsed g, centroids, centroids_mapping, centers, labelized = make_graph_from_binary_img(img)
        t2 = @elapsed which = $metric(g) |> argmin
        res = centers[which][2]
        return res
    end
end

# SOME COEFFS ---
@stable function assortativity_float_factory(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
    t = @elapsed g, centroids, centroids_mapping, centers, labelized = make_graph_from_binary_img(img)
    t2 = @elapsed res = assortativity(g)

    return res
end
@stable function global_clustering_coefficient_float_factory(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
    t = @elapsed g, centroids, centroids_mapping, centers, labelized = make_graph_from_binary_img(img)
    t2 = @elapsed res = global_clustering_coefficient(g)

    return res
end
@stable function diameter_float_factory(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
    t = @elapsed g, centroids, centroids_mapping, centers, labelized = make_graph_from_binary_img(img)
    t2 = @elapsed res = diameter(g)

    return res
end

# SPECIAL COMMUNITIES
@stable function label_propagation_factory(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
    t = @elapsed g, centroids, centroids_mapping, centers, labelized = make_graph_from_binary_img(img)
    t2 = @elapsed res = label_propagation(g)[1] |> unique |> length # nb of communities

    return res
end

# BUNDLES --- ---
append_method!(bundle_float_imagegraph, meanbetweenness_centrality_float_factory, :meanbetweennesscentrality)
append_method!(bundle_float_imagegraph, medianbetweenness_centrality_float_factory, :medianbetweennesscentrality)
append_method!(bundle_float_imagegraph, minimumbetweenness_centrality_float_factory, :minimumbetweennesscentrality)
append_method!(bundle_float_imagegraph, maximumbetweenness_centrality_float_factory, :maximumbetweennesscentrality)
append_method!(bundle_float_imagegraph, stdbetweenness_centrality_float_factory, :stdbetweennesscentrality)
append_method!(bundle_float_imagegraph, xCoorArgmaxbetweenness_centrality_float_factory, :xcoorargmaxbetweennesscentrality)
append_method!(bundle_float_imagegraph, yCoorArgmaxbetweenness_centrality_float_factory, :ycoorargmaxbetweennesscentrality)
append_method!(bundle_float_imagegraph, xCoorArgminbetweenness_centrality_float_factory, :xcoorargminbetweennesscentrality)
append_method!(bundle_float_imagegraph, yCoorArgminbetweenness_centrality_float_factory, :ycoorargminbetweennesscentrality)

append_method!(bundle_float_imagegraph, meancloseness_centrality_float_factory, :meanclosenesscentrality)
append_method!(bundle_float_imagegraph, mediancloseness_centrality_float_factory, :medianclosenesscentrality)
append_method!(bundle_float_imagegraph, minimumcloseness_centrality_float_factory, :minimumclosenesscentrality)
append_method!(bundle_float_imagegraph, maximumcloseness_centrality_float_factory, :maximumclosenesscentrality)
append_method!(bundle_float_imagegraph, stdcloseness_centrality_float_factory, :stdclosenesscentrality)
append_method!(bundle_float_imagegraph, xCoorArgmaxcloseness_centrality_float_factory, :xcoorargmaxclosenesscentrality)
append_method!(bundle_float_imagegraph, yCoorArgmaxcloseness_centrality_float_factory, :ycoorargmaxclosenesscentrality)
append_method!(bundle_float_imagegraph, xCoorArgmincloseness_centrality_float_factory, :xcoorargminclosenesscentrality)
append_method!(bundle_float_imagegraph, yCoorArgmincloseness_centrality_float_factory, :ycoorargminclosenesscentrality)

append_method!(bundle_float_imagegraph, meandegree_centrality_float_factory, :meandegreecentrality)
append_method!(bundle_float_imagegraph, mediandegree_centrality_float_factory, :mediandegreecentrality)
append_method!(bundle_float_imagegraph, minimumdegree_centrality_float_factory, :minimumdegreecentrality)
append_method!(bundle_float_imagegraph, maximumdegree_centrality_float_factory, :maximumdegreecentrality)
append_method!(bundle_float_imagegraph, stddegree_centrality_float_factory, :stddegreecentrality)
append_method!(bundle_float_imagegraph, xCoorArgmaxdegree_centrality_float_factory, :xcoorargmaxdegreecentrality)
append_method!(bundle_float_imagegraph, yCoorArgmaxdegree_centrality_float_factory, :ycoorargmaxdegreecentrality)
append_method!(bundle_float_imagegraph, xCoorArgmindegree_centrality_float_factory, :xcoorargmindegreecentrality)
append_method!(bundle_float_imagegraph, yCoorArgmindegree_centrality_float_factory, :ycoorargmindegreecentrality)

append_method!(bundle_float_imagegraph, meanindegree_centrality_float_factory, :meanindegreecentrality)
append_method!(bundle_float_imagegraph, medianindegree_centrality_float_factory, :medianindegreecentrality)
append_method!(bundle_float_imagegraph, minimumindegree_centrality_float_factory, :minimumindegreecentrality)
append_method!(bundle_float_imagegraph, maximumindegree_centrality_float_factory, :maximumindegreecentrality)
append_method!(bundle_float_imagegraph, stdindegree_centrality_float_factory, :stdindegreecentrality)
append_method!(bundle_float_imagegraph, xCoorArgmaxindegree_centrality_float_factory, :xcoorargmaxindegreecentrality)
append_method!(bundle_float_imagegraph, yCoorArgmaxindegree_centrality_float_factory, :ycoorargmaxindegreecentrality)
append_method!(bundle_float_imagegraph, xCoorArgminindegree_centrality_float_factory, :xcoorargminindegreecentrality)
append_method!(bundle_float_imagegraph, yCoorArgminindegree_centrality_float_factory, :ycoorargminindegreecentrality)

append_method!(bundle_float_imagegraph, meanoutdegree_centrality_float_factory, :meanoutdegreecentrality)
append_method!(bundle_float_imagegraph, medianoutdegree_centrality_float_factory, :medianoutdegreecentrality)
append_method!(bundle_float_imagegraph, minimumoutdegree_centrality_float_factory, :minimumoutdegreecentrality)
append_method!(bundle_float_imagegraph, maximumoutdegree_centrality_float_factory, :maximumoutdegreecentrality)
append_method!(bundle_float_imagegraph, stdoutdegree_centrality_float_factory, :stdoutdegreecentrality)
append_method!(bundle_float_imagegraph, xCoorArgmaxoutdegree_centrality_float_factory, :xcoorargmaxoutdegreecentrality)
append_method!(bundle_float_imagegraph, yCoorArgmaxoutdegree_centrality_float_factory, :ycoorargmaxoutdegreecentrality)
append_method!(bundle_float_imagegraph, xCoorArgminoutdegree_centrality_float_factory, :xcoorargminoutdegreecentrality)
append_method!(bundle_float_imagegraph, yCoorArgminoutdegree_centrality_float_factory, :ycoorargminoutdegreecentrality)

append_method!(bundle_float_imagegraph, meaneigenvector_centrality_float_factory, :meaneigenvectorcentrality)
append_method!(bundle_float_imagegraph, medianeigenvector_centrality_float_factory, :medianeigenvectorcentrality)
append_method!(bundle_float_imagegraph, minimumeigenvector_centrality_float_factory, :minimumeigenvectorcentrality)
append_method!(bundle_float_imagegraph, maximumeigenvector_centrality_float_factory, :maximumeigenvectorcentrality)
append_method!(bundle_float_imagegraph, stdeigenvector_centrality_float_factory, :stdeigenvectorcentrality)
append_method!(bundle_float_imagegraph, xCoorArgmaxeigenvector_centrality_float_factory, :xcoorargmaxeigenvectorcentrality)
append_method!(bundle_float_imagegraph, yCoorArgmaxeigenvector_centrality_float_factory, :ycoorargmaxeigenvectorcentrality)
append_method!(bundle_float_imagegraph, xCoorArgmineigenvector_centrality_float_factory, :xcoorargmineigenvectorcentrality)
append_method!(bundle_float_imagegraph, yCoorArgmineigenvector_centrality_float_factory, :ycoorargmineigenvectorcentrality)

append_method!(bundle_float_imagegraph, meanradiality_centrality_float_factory, :meanradialitycentrality)
append_method!(bundle_float_imagegraph, medianradiality_centrality_float_factory, :medianradialitycentrality)
append_method!(bundle_float_imagegraph, minimumradiality_centrality_float_factory, :minimumradialitycentrality)
append_method!(bundle_float_imagegraph, maximumradiality_centrality_float_factory, :maximumradialitycentrality)
append_method!(bundle_float_imagegraph, stdradiality_centrality_float_factory, :stdradialitycentrality)
append_method!(bundle_float_imagegraph, xCoorArgmaxradiality_centrality_float_factory, :xcoorargmaxradialitycentrality)
append_method!(bundle_float_imagegraph, yCoorArgmaxradiality_centrality_float_factory, :ycoorargmaxradialitycentrality)
append_method!(bundle_float_imagegraph, xCoorArgminradiality_centrality_float_factory, :xcoorargminradialitycentrality)
append_method!(bundle_float_imagegraph, yCoorArgminradiality_centrality_float_factory, :ycoorargminradialitycentrality)

append_method!(bundle_float_imagegraph, meanstress_centrality_float_factory, :meanstresscentrality)
append_method!(bundle_float_imagegraph, medianstress_centrality_float_factory, :medianstresscentrality)
append_method!(bundle_float_imagegraph, minimumstress_centrality_float_factory, :minimumstresscentrality)
append_method!(bundle_float_imagegraph, maximumstress_centrality_float_factory, :maximumstresscentrality)
append_method!(bundle_float_imagegraph, stdstress_centrality_float_factory, :stdstresscentrality)
append_method!(bundle_float_imagegraph, xCoorArgmaxstress_centrality_float_factory, :xcoorargmaxstresscentrality)
append_method!(bundle_float_imagegraph, yCoorArgmaxstress_centrality_float_factory, :ycoorargmaxstresscentrality)
append_method!(bundle_float_imagegraph, xCoorArgminstress_centrality_float_factory, :xcoorargminstresscentrality)
append_method!(bundle_float_imagegraph, yCoorArgminstress_centrality_float_factory, :ycoorargminstresscentrality)

append_method!(bundle_float_imagegraph, meanlocal_clustering_coefficient_float_factory, :meanclusteringcoefficient)
append_method!(bundle_float_imagegraph, medianlocal_clustering_coefficient_float_factory, :medianclusteringcoefficient)
append_method!(bundle_float_imagegraph, minimumlocal_clustering_coefficient_float_factory, :minimumclusteringcoefficient)
append_method!(bundle_float_imagegraph, maximumlocal_clustering_coefficient_float_factory, :maximumclusteringcoefficient)
append_method!(bundle_float_imagegraph, stdlocal_clustering_coefficient_float_factory, :stdclusteringcoefficient)
append_method!(bundle_float_imagegraph, xCoorArgmaxlocal_clustering_coefficient_float_factory, :xcoorargmaxclusteringcoefficient)
append_method!(bundle_float_imagegraph, yCoorArgmaxlocal_clustering_coefficient_float_factory, :ycoorargmaxclusteringcoefficient)
append_method!(bundle_float_imagegraph, xCoorArgminlocal_clustering_coefficient_float_factory, :xcoorargminclusteringcoefficient)
append_method!(bundle_float_imagegraph, yCoorArgminlocal_clustering_coefficient_float_factory, :ycoorargminclusteringcoefficient)

append_method!(bundle_float_imagegraph, meantriangles_float_factory, :meantriangles)
append_method!(bundle_float_imagegraph, mediantriangles_float_factory, :mediantriangles)
append_method!(bundle_float_imagegraph, minimumtriangles_float_factory, :minimumtriangles)
append_method!(bundle_float_imagegraph, maximumtriangles_float_factory, :maximumtriangles)
append_method!(bundle_float_imagegraph, stdtriangles_float_factory, :stdtriangles)
append_method!(bundle_float_imagegraph, xCoorArgmaxtriangles_float_factory, :xcoorargmaxtriangles)
append_method!(bundle_float_imagegraph, yCoorArgmaxtriangles_float_factory, :ycoorargmaxtriangles)
append_method!(bundle_float_imagegraph, xCoorArgmintriangles_float_factory, :xcoorargmintriangles)
append_method!(bundle_float_imagegraph, yCoorArgmintriangles_float_factory, :ycoorargmintriangles)

append_method!(bundle_float_imagegraph, meaneccentricity_float_factory, :meaneccentricity)
append_method!(bundle_float_imagegraph, medianeccentricity_float_factory, :medianeccentricity)
append_method!(bundle_float_imagegraph, minimumeccentricity_float_factory, :minimumeccentricity)
append_method!(bundle_float_imagegraph, maximumeccentricity_float_factory, :maximumeccentricity)
append_method!(bundle_float_imagegraph, stdeccentricity_float_factory, :stdeccentricity)
append_method!(bundle_float_imagegraph, xCoorArgmaxeccentricity_float_factory, :xcoorargmaxeccentricity)
append_method!(bundle_float_imagegraph, yCoorArgmaxeccentricity_float_factory, :ycoorargmaxeccentricity)
append_method!(bundle_float_imagegraph, xCoorArgmineccentricity_float_factory, :xcoorargmineccentricity)
append_method!(bundle_float_imagegraph, yCoorArgmineccentricity_float_factory, :ycoorargmineccentricity)

# COEFFS ---
append_method!(bundle_float_imagegraph, assortativity_float_factory, :assortativity)
append_method!(bundle_float_imagegraph, global_clustering_coefficient_float_factory, :clustering_coefficient)
append_method!(bundle_float_imagegraph, diameter_float_factory, :diameter)

# COMMUNITIES ---
append_method!(bundle_float_imagegraph, label_propagation_factory, :label_propagation)

end


# GRAPH BUT FOR IMAGE --- TODO
# fns = [
#     betweenness_centrality,
#     closeness_centrality,
#     degree_centrality,
#     indegree_centrality,
#     outdegree_centrality,
#     eigenvector_centrality,
#     radiality_centrality,
#     stress_centrality,
#     local_clustering_coefficient,
#     triangles,
#     eccentricity
# ]
# FOR BINARY LIB

# KEEP IF ABOVE
# mask = eigenvector_centrality(g) .> 0.1
# keep = collect(1:length(vertices(g)))[mask]
# segments = [centroids_mapping[k] for k in keep]
# remove other segments
# for (ith_p, p) in enumerate(labelized)
#     if !(p in segments)
#         labelized[ith_p] = 0
#     end
# end
# tobin :SImageND(BinaryPixel.(labelized .> 1))

# KEEP IF BELOW
# mask = eigenvector_centrality(g) .< 0.1
# keep = collect(1:length(vertices(g)))[mask]
# segments = [centroids_mapping[k] for k in keep]
# remove other segments
# for (ith_p, p) in enumerate(labelized)
#     if !(p in segments)
#         labelized[ith_p] = 0
#     end
# end
# tobin :SImageND(BinaryPixel.(labelized .> 1))

# KEEP IF
# periphery # => keep highest eccentricity
# center # => keep smallest eccentricity

# COMMUNITY DETECTION
# can segment with label_propagation(g)[1] |> unique
