using Images, ImageSegmentation, Statistics
using ImageView
using ImageSegmentation, Statistics
using DelaunayTriangulation
using Graphs
using GraphPlot, Colors
using UTCGP

img = load("assets/000_img.png")
red_channel = red.(img)
img = SImageND(BinaryPixel.(red_channel .> 0.1))

threshold_value = otsu_threshold(nuclei)
nuclei = red_channel
binary_nuclei = nuclei .> threshold_value

labelized = label_components(binary_nuclei)
labels = unique(labelized)
centroids = Dict()
for label in labels
   # Find all pixels with this label
   indices = findall(labelized .== label)
   # Convert to row, column coordinates
   coords = [(ind[1], ind[2]) for ind in indices]
   # Calculate centroid
   y_coords = [c[1] for c in coords]
   x_coords = [c[2] for c in coords]
   centroids[label] = (mean(y_coords), mean(x_coords))
end
cell_centers = collect(values(centroids))
n_cells = length(cell_centers)
points = [(Float64(p[1]), Float64(p[2])) for p in cell_centers]
tri = triangulate(points)

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

function visualize_cell_graph(img, cell_centers, g, lightup = [])
    # Display the original image
    img_to_display = RGB{N0f8}.(img)
    
    # Overlay graph
    for e in Graphs.edges(g)
        src = cell_centers[Graphs.src(e)]
        dst = cell_centers[Graphs.dst(e)]
        p1 = Point(Int(round(src[2])), Int(round(src[1])))
        p2 = Point(Int(round(dst[2])), Int(round(dst[1]))) 

        if e.src in lightup 
            @show e.src
            draw!(img_to_display , Ellipse(CirclePointRadius(p1,10)), RGB{N0f8}(0.1,0.5,0.7))
        end
        if e.dst in lightup 
            @show e.dst
            draw!(img_to_display , Ellipse(CirclePointRadius(p2,10)), RGB{N0f8}(0.1,0.5,0.7))
        end
        draw!(img_to_display, LineSegment(p1, p2), RGB{N0f8}(0,0,1))
        # draw!(img_to_display , Ellipse(CirclePointRadius(p1,2)), RGB{N0f8}(1,0,1))
        # draw!(img_to_display , Ellipse(CirclePointRadius(p2,2)), RGB{N0f8}(1,0,1))
    end
    
    # Mark cell centers
    # for center in cell_centers        
    #     @show center
    #     p1 = Int(round(center[1]))
    #     p2 = Int(round(center[2]))
    #     p = Point(p1, p2)
    #     draw!(img_to_display , Ellipse(CirclePointRadius(p,10)), RGB{N0f8}(1,0,1))
    # end
    
    return img_to_display 
end
result = visualize_cell_graph(img, cell_centers, g)
# save("cell_graph.png", result)
#
#

# name = :meanbetweenness_centrality_float_factory
# name = :medianbetweenness_centrality_float_factory
# name = :minimumbetweenness_centrality_float_factory
# name = :maximumbetweenness_centrality_float_factory
# name = :stdbetweenness_centrality_float_factory
# name = :xCoorArgmaxbetweenness_centrality_float_factory
# name = :yCoorArgmaxbetweenness_centrality_float_factory
# name = :xCoorArgminbetweenness_centrality_float_factory
# name = :yCoorArgminbetweenness_centrality_float_factory
# name = :meancloseness_centrality_float_factory
# name = :mediancloseness_centrality_float_factory
# name = :minimumcloseness_centrality_float_factory
# name = :maximumcloseness_centrality_float_factory
# name = :stdcloseness_centrality_float_factory
# name = :xCoorArgmaxcloseness_centrality_float_factory
# name = :yCoorArgmaxcloseness_centrality_float_factory
# name = :xCoorArgmincloseness_centrality_float_factory
# name = :yCoorArgmincloseness_centrality_float_factory
# name = :meandegree_centrality_float_factory
# name = :mediandegree_centrality_float_factory
# name = :minimumdegree_centrality_float_factory
# name = :maximumdegree_centrality_float_factory
# name = :stddegree_centrality_float_factory
# name = :xCoorArgmaxdegree_centrality_float_factory
# name = :yCoorArgmaxdegree_centrality_float_factory
# name = :xCoorArgmindegree_centrality_float_factory
# name = :yCoorArgmindegree_centrality_float_factory
# name = :meanindegree_centrality_float_factory
# name = :medianindegree_centrality_float_factory
# name = :minimumindegree_centrality_float_factory
# name = :maximumindegree_centrality_float_factory
# name = :stdindegree_centrality_float_factory
# name = :xCoorArgmaxindegree_centrality_float_factory
# name = :yCoorArgmaxindegree_centrality_float_factory
# name = :xCoorArgminindegree_centrality_float_factory
# name = :yCoorArgminindegree_centrality_float_factory
# name = :meanoutdegree_centrality_float_factory
# name = :medianoutdegree_centrality_float_factory
# name = :minimumoutdegree_centrality_float_factory
# name = :maximumoutdegree_centrality_float_factory
# name = :stdoutdegree_centrality_float_factory
# name = :xCoorArgmaxoutdegree_centrality_float_factory
# name = :yCoorArgmaxoutdegree_centrality_float_factory
# name = :xCoorArgminoutdegree_centrality_float_factory
# name = :yCoorArgminoutdegree_centrality_float_factory
# name = :meaneigenvector_centrality_float_factory
# name = :medianeigenvector_centrality_float_factory
# name = :minimumeigenvector_centrality_float_factory
# name = :maximumeigenvector_centrality_float_factory
# name = :stdeigenvector_centrality_float_factory
# name = :xCoorArgmaxeigenvector_centrality_float_factory
# name = :yCoorArgmaxeigenvector_centrality_float_factory
# name = :xCoorArgmineigenvector_centrality_float_factory
# name = :yCoorArgmineigenvector_centrality_float_factory
# name = :meanradiality_centrality_float_factory
# name = :medianradiality_centrality_float_factory
# name = :minimumradiality_centrality_float_factory
# name = :maximumradiality_centrality_float_factory
# name = :stdradiality_centrality_float_factory
# name = :xCoorArgmaxradiality_centrality_float_factory
# name = :yCoorArgmaxradiality_centrality_float_factory
# name = :xCoorArgminradiality_centrality_float_factory
# name = :yCoorArgminradiality_centrality_float_factory
# name = :meanstress_centrality_float_factory
# name = :medianstress_centrality_float_factory
# name = :minimumstress_centrality_float_factory
# name = :maximumstress_centrality_float_factory
# name = :stdstress_centrality_float_factory
# name = :xCoorArgmaxstress_centrality_float_factory
# name = :yCoorArgmaxstress_centrality_float_factory
# name = :xCoorArgminstress_centrality_float_factory
# name = :yCoorArgminstress_centrality_float_factory
# name = :meanlocal_clustering_coefficient_float_factory
# name = :medianlocal_clustering_coefficient_float_factory
# name = :minimumlocal_clustering_coefficient_float_factory
# name = :maximumlocal_clustering_coefficient_float_factory
# name = :stdlocal_clustering_coefficient_float_factory
# name = :xCoorArgmaxlocal_clustering_coefficient_float_factory
# name = :yCoorArgmaxlocal_clustering_coefficient_float_factory
# name = :xCoorArgminlocal_clustering_coefficient_float_factory
# name = :yCoorArgminlocal_clustering_coefficient_float_factory
# name = :meantriangles_float_factory
# name = :mediantriangles_float_factory
# name = :minimumtriangles_float_factory
# name = :maximumtriangles_float_factory
# name = :stdtriangles_float_factory
# name = :xCoorArgmaxtriangles_float_factory
# name = :yCoorArgmaxtriangles_float_factory
# name = :xCoorArgmintriangles_float_factory
# name = :yCoorArgmintriangles_float_factory
# name = :meaneccentricity_float_factory
# name = :medianeccentricity_float_factory
# name = :minimumeccentricity_float_factory
# name = :maximumeccentricity_float_factory
# name = :stdeccentricity_float_factory
# name = :xCoorArgmaxeccentricity_float_factory
# name = :yCoorArgmaxeccentricity_float_factory
# name = :xCoorArgmineccentricity_float_factory
# name = :yCoorArgmineccentricity_float_factory
