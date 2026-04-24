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
using ImageSegmentation, Statistics
using DelaunayTriangulation
using Graphs
using Random
using DispatchDoctor
using Statistics
using LinearAlgebra
import Delaunator

function DelaunayTriangulation.get_triangles(tri::Delaunator.Triangulation)
    return collect(Delaunator.triangles(tri))
end

# using GraphPlot, Colors

"""
is_collinear(points; reltol=1e-12)

Check if a set of 2D points (2×N matrix) is approximately collinear.

"""
function is_collinear(points::AbstractMatrix{Float64}; reltol = 1.0e-12)
    N = size(points, 2)
    @assert size(points, 1) == 2 "Input must be 2×N matrix"

    if N <= 2
        return true, collect(1:N)
    end

    # Center points
    meanP = mean(points, dims = 2)
    C = points .- meanP

    # Use SVD to get principal axis
    s = svd(C).S
    if s[end] < reltol * (s[1] + eps())   # smallest singular value small → nearly collinear
        ## Project onto first principal axis for ordering
        #V = svd(C).V[:,1]
        #t = vec(V' * C)       # scalar projection of each point
        #ord = sortperm(t)
        return true, s
    else
        return false, s
    end
end

function make_graph_from_binary_img(img, r = 1)
    labelized = label_components(img, strel_box(img; r = r))
    labels = unique(labelized)

    if length(labels) <= 3
        throw(DimensionMismatch("Only two centers for triangulation"))
    end

    # centroids = Dict()
    # centroids_mapping = Dict()
    # for (i, label) in enumerate(labels)
    #     # Find all pixels with this label
    #     indices = findall(labelized .== label)
    #     # Convert to row, column coordinates
    #     coords = [(ind[1], ind[2]) for ind in indices]
    #     # Calculate centroid
    #     y_coords = [c[1] for c in coords]
    #     x_coords = [c[2] for c in coords]
    #     centroids[label] = (mean(y_coords), mean(x_coords))
    #     centroids_mapping[i] = label
    # end
    # cell_centers = collect(values(centroids))
    # n_cells = length(cell_centers) # LEGACY SINCE components_centroids does that

    cell_centers = collect(component_centroids(labelized))[2:end]
    n_cells = length(cell_centers)
    if n_cells > 1000
        # if isdefined(Main, :Infiltrator)
        #     Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        # end
        @warn "A lot of cells $n_cells"
    end
    points = [(Float64(p[1]), Float64(p[2])) for p in cell_centers]
    # points_matrix = round.(reshape(reduce(vcat, collect.(points)), (2, :)), digits = 0)
    points_matrix = reshape(reduce(vcat, collect.(points)), (2, :))
    points_matrix .+= randn(Xoshiro(0), size(points_matrix)) * 1.0e-8

    failed, s = is_collinear(points_matrix; reltol = 1.0e-8)
    if failed
        # if isdefined(Main, :Infiltrator)
        #     Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        # end
        @warn "Not triangulating because possibly degenerate $s"
        DomainError("colinear") |> throw
    end

    # println(points_matrix)
    # print(failed)
    t = @elapsed tri = Delaunator.triangulate(Delaunator.PointsFromMatrix(points_matrix))
    # t = @elapsed tri = triangulate(points_matrix; rng = Xoshiro(0), predicates = DelaunayTriangulation.FastKernel(), randomise = false, delete_ghosts = true)
    if t > 0.1
        @warn "Triangulation was costly $t"
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

    return g, centroids, centroids_mapping, cell_centers, labelized, tri
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
        @eval function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
            g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img)
            res = $metric(g) |> $(stat)
            return res
        end
        @eval function $name(img::SizedImage{S, <:BinaryPixel}, r::Number, args::Vararg{Any}) where {S}
            r_ = r > 0 ? 1 : 2
            g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img, r_)
            res = $metric(g) |> $(stat)
            return res
        end
    end

    name = Symbol("xCoorArgmax$(metric)_float_factory")
    @show name
    @eval function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
        g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img)
        which = $metric(g) |> argmax
        res = centers[which][1]
        return res
    end

    name = Symbol("yCoorArgmax$(metric)_float_factory")
    @show name
    @eval function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
        g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img)
        which = $metric(g) |> argmax
        return centers[which][2]
    end

    name = Symbol("xCoorArgmin$(metric)_float_factory")
    @show name
    @eval function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
        g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img)
        which = $metric(g) |> argmin
        res = centers[which][1]
        return res
    end

    name = Symbol("yCoorArgmin$(metric)_float_factory")
    @show name
    @eval function $name(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
        g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img)
        which = $metric(g) |> argmin
        res = centers[which][2]
        return res
    end
end

# SOME COEFFS ---
function assortativity_float_factory(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
    g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img)
    res = assortativity(g)
    return res
end
function global_clustering_coefficient_float_factory(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
    g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img)
    res = global_clustering_coefficient(g)
    return res
end
function diameter_float_factory(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
    g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img)
    res = diameter(g)
    return res
end

# SPECIAL COMMUNITIES
function label_propagation_factory(img::SizedImage{S, <:BinaryPixel}, args::Vararg{Any}) where {S}
    g, centroids, centroids_mapping, centers, labelized, tri = make_graph_from_binary_img(img)
    res = label_propagation(g)[1] |> unique |> length # nb of communities
    return res
end

function _image_graph_description(name::Symbol)::String
    s = lowercase(String(name))
    metric = s
    reducer = ""

    if startswith(metric, "xcoorargmax")
        metric = replace(metric, "xcoorargmax" => "")
        reducer = "x-coordinate of argmax"
    elseif startswith(metric, "ycoorargmax")
        metric = replace(metric, "ycoorargmax" => "")
        reducer = "y-coordinate of argmax"
    elseif startswith(metric, "xcoorargmin")
        metric = replace(metric, "xcoorargmin" => "")
        reducer = "x-coordinate of argmin"
    elseif startswith(metric, "ycoorargmin")
        metric = replace(metric, "ycoorargmin" => "")
        reducer = "y-coordinate of argmin"
    elseif startswith(metric, "mean")
        metric = replace(metric, "mean" => "")
        reducer = "mean"
    elseif startswith(metric, "median")
        metric = replace(metric, "median" => "")
        reducer = "median"
    elseif startswith(metric, "minimum")
        metric = replace(metric, "minimum" => "")
        reducer = "minimum"
    elseif startswith(metric, "maximum")
        metric = replace(metric, "maximum" => "")
        reducer = "maximum"
    elseif startswith(metric, "std")
        metric = replace(metric, "std" => "")
        reducer = "standard deviation"
    end

    metric_h = replace(metric, "centrality" => " centrality")
    metric_h = replace(metric_h, "clusteringcoefficient" => "clustering coefficient")
    metric_h = replace(metric_h, "stress" => "stress")
    metric_h = replace(metric_h, "triangles" => "triangles")
    metric_h = strip(metric_h)

    if s == "assortativity"
        return "Computes graph assortativity on the graph built from the binary image."
    elseif s == "clustering_coefficient"
        return "Computes the global clustering coefficient of the graph built from the binary image."
    elseif s == "diameter"
        return "Computes the graph diameter on the graph built from the binary image."
    elseif s == "label_propagation"
        return "Computes the number of detected communities from label propagation on the image graph."
    elseif !isempty(reducer)
        return "Computes the node-wise $(metric_h) vector on the image graph, then returns the $(reducer) over that vector."
    end
    return "Computes a graph-based feature from the binary-image graph representation."
end

function append_image_graph_metric!(factory, name::Symbol)
    return append_method!(
        bundle_float_imagegraph,
        factory,
        name;
        description = _image_graph_description(name),
    )
end

# BUNDLES --- ---
append_image_graph_metric!(meanbetweenness_centrality_float_factory, :meanbetweennesscentrality)
append_image_graph_metric!(medianbetweenness_centrality_float_factory, :medianbetweennesscentrality)
append_image_graph_metric!(minimumbetweenness_centrality_float_factory, :minimumbetweennesscentrality)
append_image_graph_metric!(maximumbetweenness_centrality_float_factory, :maximumbetweennesscentrality)
append_image_graph_metric!(stdbetweenness_centrality_float_factory, :stdbetweennesscentrality)
append_image_graph_metric!(xCoorArgmaxbetweenness_centrality_float_factory, :xcoorargmaxbetweennesscentrality)
append_image_graph_metric!(yCoorArgmaxbetweenness_centrality_float_factory, :ycoorargmaxbetweennesscentrality)
append_image_graph_metric!(xCoorArgminbetweenness_centrality_float_factory, :xcoorargminbetweennesscentrality)
append_image_graph_metric!(yCoorArgminbetweenness_centrality_float_factory, :ycoorargminbetweennesscentrality)

append_image_graph_metric!(meancloseness_centrality_float_factory, :meanclosenesscentrality)
append_image_graph_metric!(mediancloseness_centrality_float_factory, :medianclosenesscentrality)
append_image_graph_metric!(minimumcloseness_centrality_float_factory, :minimumclosenesscentrality)
append_image_graph_metric!(maximumcloseness_centrality_float_factory, :maximumclosenesscentrality)
append_image_graph_metric!(stdcloseness_centrality_float_factory, :stdclosenesscentrality)
append_image_graph_metric!(xCoorArgmaxcloseness_centrality_float_factory, :xcoorargmaxclosenesscentrality)
append_image_graph_metric!(yCoorArgmaxcloseness_centrality_float_factory, :ycoorargmaxclosenesscentrality)
append_image_graph_metric!(xCoorArgmincloseness_centrality_float_factory, :xcoorargminclosenesscentrality)
append_image_graph_metric!(yCoorArgmincloseness_centrality_float_factory, :ycoorargminclosenesscentrality)

append_image_graph_metric!(meandegree_centrality_float_factory, :meandegreecentrality)
append_image_graph_metric!(mediandegree_centrality_float_factory, :mediandegreecentrality)
append_image_graph_metric!(minimumdegree_centrality_float_factory, :minimumdegreecentrality)
append_image_graph_metric!(maximumdegree_centrality_float_factory, :maximumdegreecentrality)
append_image_graph_metric!(stddegree_centrality_float_factory, :stddegreecentrality)
append_image_graph_metric!(xCoorArgmaxdegree_centrality_float_factory, :xcoorargmaxdegreecentrality)
append_image_graph_metric!(yCoorArgmaxdegree_centrality_float_factory, :ycoorargmaxdegreecentrality)
append_image_graph_metric!(xCoorArgmindegree_centrality_float_factory, :xcoorargmindegreecentrality)
append_image_graph_metric!(yCoorArgmindegree_centrality_float_factory, :ycoorargmindegreecentrality)

append_image_graph_metric!(meanindegree_centrality_float_factory, :meanindegreecentrality)
append_image_graph_metric!(medianindegree_centrality_float_factory, :medianindegreecentrality)
append_image_graph_metric!(minimumindegree_centrality_float_factory, :minimumindegreecentrality)
append_image_graph_metric!(maximumindegree_centrality_float_factory, :maximumindegreecentrality)
append_image_graph_metric!(stdindegree_centrality_float_factory, :stdindegreecentrality)
append_image_graph_metric!(xCoorArgmaxindegree_centrality_float_factory, :xcoorargmaxindegreecentrality)
append_image_graph_metric!(yCoorArgmaxindegree_centrality_float_factory, :ycoorargmaxindegreecentrality)
append_image_graph_metric!(xCoorArgminindegree_centrality_float_factory, :xcoorargminindegreecentrality)
append_image_graph_metric!(yCoorArgminindegree_centrality_float_factory, :ycoorargminindegreecentrality)

append_image_graph_metric!(meanoutdegree_centrality_float_factory, :meanoutdegreecentrality)
append_image_graph_metric!(medianoutdegree_centrality_float_factory, :medianoutdegreecentrality)
append_image_graph_metric!(minimumoutdegree_centrality_float_factory, :minimumoutdegreecentrality)
append_image_graph_metric!(maximumoutdegree_centrality_float_factory, :maximumoutdegreecentrality)
append_image_graph_metric!(stdoutdegree_centrality_float_factory, :stdoutdegreecentrality)
append_image_graph_metric!(xCoorArgmaxoutdegree_centrality_float_factory, :xcoorargmaxoutdegreecentrality)
append_image_graph_metric!(yCoorArgmaxoutdegree_centrality_float_factory, :ycoorargmaxoutdegreecentrality)
append_image_graph_metric!(xCoorArgminoutdegree_centrality_float_factory, :xcoorargminoutdegreecentrality)
append_image_graph_metric!(yCoorArgminoutdegree_centrality_float_factory, :ycoorargminoutdegreecentrality)

append_image_graph_metric!(meaneigenvector_centrality_float_factory, :meaneigenvectorcentrality)
append_image_graph_metric!(medianeigenvector_centrality_float_factory, :medianeigenvectorcentrality)
append_image_graph_metric!(minimumeigenvector_centrality_float_factory, :minimumeigenvectorcentrality)
append_image_graph_metric!(maximumeigenvector_centrality_float_factory, :maximumeigenvectorcentrality)
append_image_graph_metric!(stdeigenvector_centrality_float_factory, :stdeigenvectorcentrality)
append_image_graph_metric!(xCoorArgmaxeigenvector_centrality_float_factory, :xcoorargmaxeigenvectorcentrality)
append_image_graph_metric!(yCoorArgmaxeigenvector_centrality_float_factory, :ycoorargmaxeigenvectorcentrality)
append_image_graph_metric!(xCoorArgmineigenvector_centrality_float_factory, :xcoorargmineigenvectorcentrality)
append_image_graph_metric!(yCoorArgmineigenvector_centrality_float_factory, :ycoorargmineigenvectorcentrality)

append_image_graph_metric!(meanradiality_centrality_float_factory, :meanradialitycentrality)
append_image_graph_metric!(medianradiality_centrality_float_factory, :medianradialitycentrality)
append_image_graph_metric!(minimumradiality_centrality_float_factory, :minimumradialitycentrality)
append_image_graph_metric!(maximumradiality_centrality_float_factory, :maximumradialitycentrality)
append_image_graph_metric!(stdradiality_centrality_float_factory, :stdradialitycentrality)
append_image_graph_metric!(xCoorArgmaxradiality_centrality_float_factory, :xcoorargmaxradialitycentrality)
append_image_graph_metric!(yCoorArgmaxradiality_centrality_float_factory, :ycoorargmaxradialitycentrality)
append_image_graph_metric!(xCoorArgminradiality_centrality_float_factory, :xcoorargminradialitycentrality)
append_image_graph_metric!(yCoorArgminradiality_centrality_float_factory, :ycoorargminradialitycentrality)

append_image_graph_metric!(meanstress_centrality_float_factory, :meanstresscentrality)
append_image_graph_metric!(medianstress_centrality_float_factory, :medianstresscentrality)
append_image_graph_metric!(minimumstress_centrality_float_factory, :minimumstresscentrality)
append_image_graph_metric!(maximumstress_centrality_float_factory, :maximumstresscentrality)
append_image_graph_metric!(stdstress_centrality_float_factory, :stdstresscentrality)
append_image_graph_metric!(xCoorArgmaxstress_centrality_float_factory, :xcoorargmaxstresscentrality)
append_image_graph_metric!(yCoorArgmaxstress_centrality_float_factory, :ycoorargmaxstresscentrality)
append_image_graph_metric!(xCoorArgminstress_centrality_float_factory, :xcoorargminstresscentrality)
append_image_graph_metric!(yCoorArgminstress_centrality_float_factory, :ycoorargminstresscentrality)

append_image_graph_metric!(meanlocal_clustering_coefficient_float_factory, :meanclusteringcoefficient)
append_image_graph_metric!(medianlocal_clustering_coefficient_float_factory, :medianclusteringcoefficient)
append_image_graph_metric!(minimumlocal_clustering_coefficient_float_factory, :minimumclusteringcoefficient)
append_image_graph_metric!(maximumlocal_clustering_coefficient_float_factory, :maximumclusteringcoefficient)
append_image_graph_metric!(stdlocal_clustering_coefficient_float_factory, :stdclusteringcoefficient)
append_image_graph_metric!(xCoorArgmaxlocal_clustering_coefficient_float_factory, :xcoorargmaxclusteringcoefficient)
append_image_graph_metric!(yCoorArgmaxlocal_clustering_coefficient_float_factory, :ycoorargmaxclusteringcoefficient)
append_image_graph_metric!(xCoorArgminlocal_clustering_coefficient_float_factory, :xcoorargminclusteringcoefficient)
append_image_graph_metric!(yCoorArgminlocal_clustering_coefficient_float_factory, :ycoorargminclusteringcoefficient)

append_image_graph_metric!(meantriangles_float_factory, :meantriangles)
append_image_graph_metric!(mediantriangles_float_factory, :mediantriangles)
append_image_graph_metric!(minimumtriangles_float_factory, :minimumtriangles)
append_image_graph_metric!(maximumtriangles_float_factory, :maximumtriangles)
append_image_graph_metric!(stdtriangles_float_factory, :stdtriangles)
append_image_graph_metric!(xCoorArgmaxtriangles_float_factory, :xcoorargmaxtriangles)
append_image_graph_metric!(yCoorArgmaxtriangles_float_factory, :ycoorargmaxtriangles)
append_image_graph_metric!(xCoorArgmintriangles_float_factory, :xcoorargmintriangles)
append_image_graph_metric!(yCoorArgmintriangles_float_factory, :ycoorargmintriangles)

append_image_graph_metric!(meaneccentricity_float_factory, :meaneccentricity)
append_image_graph_metric!(medianeccentricity_float_factory, :medianeccentricity)
append_image_graph_metric!(minimumeccentricity_float_factory, :minimumeccentricity)
append_image_graph_metric!(maximumeccentricity_float_factory, :maximumeccentricity)
append_image_graph_metric!(stdeccentricity_float_factory, :stdeccentricity)
append_image_graph_metric!(xCoorArgmaxeccentricity_float_factory, :xcoorargmaxeccentricity)
append_image_graph_metric!(yCoorArgmaxeccentricity_float_factory, :ycoorargmaxeccentricity)
append_image_graph_metric!(xCoorArgmineccentricity_float_factory, :xcoorargmineccentricity)
append_image_graph_metric!(yCoorArgmineccentricity_float_factory, :ycoorargmineccentricity)

# COEFFS ---
append_image_graph_metric!(assortativity_float_factory, :assortativity)
append_image_graph_metric!(global_clustering_coefficient_float_factory, :clustering_coefficient)
append_image_graph_metric!(diameter_float_factory, :diameter)

# COMMUNITIES ---
append_image_graph_metric!(label_propagation_factory, :label_propagation)

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
