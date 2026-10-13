# Standalone: never writes the runner environment. Run from MAGENetRunner root.
import Pkg
const REPRO_DIR = isdir(joinpath(@__DIR__, "POPULATION_datasets")) ? @__DIR__ : normpath(joinpath(@__DIR__, "../../POPULATION_reproducibility"))
const CLONE = normpath(joinpath(REPRO_DIR, "../POPULATION_MAGE_fastpop"))
const CHECK_ENV = mktempdir()
for name in ("Project.toml", "Manifest.toml")
    cp(joinpath(REPRO_DIR, "..", name), joinpath(CHECK_ENV,name))
end
Pkg.activate(CHECK_ENV)
Pkg.develop(path=CLONE)
using UTCGP, Random, Statistics, LinearAlgebra, Logging, Profile, JSON, SHA
BLAS.set_num_threads(1)
read_pmlb(path) = open(`gzip -dc $path`) do io
    header = split(readline(io), '\t')
    target = findfirst(==("target"), header)
    rows = [parse.(Float64, split(l, '\t')) for l in eachline(io) if !isempty(l)]
    M = reduce(vcat, permutedims.(rows))
    features = setdiff(1:length(header), [target])
    M[:, features], M[:, target], String.(header[features])
end

"""SRBench-style split: shuffled 75/25, then z-score X and y with training statistics."""
function split_scale(X, y, seed, test_frac, max_train_rows)
    rng = Xoshiro(seed)
    idx = randperm(rng, length(y))
    n_test = round(Int, test_frac * length(y))
    test, train = idx[1:n_test], idx[n_test+1:end]
    max_train_rows > 0 && length(train) > max_train_rows && (train = train[1:max_train_rows])
    μx, σx = mean(X[train, :]; dims=1), std(X[train, :]; dims=1)
    σx[σx .== 0] .= 1
    μy, σy = mean(y[train]), std(y[train])
    σy == 0 && (σy = 1.0)
    sx(A) = (A .- μx) ./ σx
    (sx(X[train, :]), (y[train] .- μy) ./ σy, sx(X[test, :]), (y[test] .- μy) ./ σy, length(train), n_test)
end

parse_constant(c) = c == "pi" ? Float64(π) : c == "e" ? Float64(ℯ) : parse(Float64, c)
parse_constants(s) = isempty(strip(s)) ? Float64[] : [parse_constant(strip(c)) for c in split(s, ',')]

"""One input tuple per row: the (scaled) features followed by the fixed constants."""
as_samples(X, constants=Float64[]) = [(X[i, :]..., constants...) for i in 1:size(X, 1)]

"""
Training MSE for every individual from the (n_individuals × n_samples) prediction matrix.

With `affine`, each individual is scored on α + β·output, with α and β fitted by least squares
(Keijzer linear scaling). The closed form gives n·MSE = Syy − Sxy²/Sxx on centred sums. One
column-major pass accumulates the sums for all individuals at once without allocating per row;
outputs are shifted by each individual's first prediction for numerical stability.
Returns (mse, α, β); a non-finite output gives Inf, and a constant output gives β = 0.
"""
function population_mse(P::Matrix{Float64}, y::Vector{Float64}, affine::Bool, clip_bounds=nothing)
    n, m = size(P)
    mse = zeros(n); α = zeros(n); β = ones(n)
    if !affine
        for j in 1:m, i in 1:n
            mse[i] += (P[i, j] - y[j])^2
        end
        mse ./= m
    else
        ȳ = sum(y) / m
        Syy = sum(t -> (t - ȳ)^2, y)
        shift = P[:, 1]
        Sx = zeros(n); Sxx = zeros(n); Sxy = zeros(n)
        for j in 1:m
            yc = y[j] - ȳ
            @inbounds @simd for i in 1:n
                x = P[i, j] - shift[i]
                Sx[i] += x; Sxx[i] += x * x; Sxy[i] += x * yc
            end
        end
        for i in 1:n
            sxx = Sxx[i] - Sx[i]^2 / m          # centred Σ(x - x̄)²
            if !isfinite(sxx) || !isfinite(Sxy[i])
                mse[i] = Inf
            elseif sxx > 0
                β[i] = Sxy[i] / sxx              # Σ(x - x̄)(y - ȳ) = Σ x(y - ȳ)
                α[i] = ȳ - β[i] * (shift[i] + Sx[i] / m)
                mse[i] = max(Syy - Sxy[i]^2 / sxx, 0.0) / m
            else
                β[i] = 0.0; α[i] = ȳ; mse[i] = Syy / m
            end
        end
    end
    if clip_bounds !== nothing
        for i in 1:n
            isfinite(mse[i]) || continue
            mse[i] = sum((clamp(α[i] + β[i] * P[i,j], clip_bounds...) - y[j])^2 for j in 1:m) / m
        end
    end
    for i in 1:n
        isfinite(mse[i]) || (mse[i] = Inf)
    end
    mse, α, β
end


compile_all(programs, arch, ml, n) =
    UTCGP.SequentialProgram[UTCGP.compile_program(programs[i], arch, ml; safe=true) for i in 1:n]

"""Separate graph per individual, same thread layout as the shared evaluator."""
function eval_indiv(graphs, samples, n)
    out = Matrix{Float64}(undef, n, length(samples))
    workspaces = [[UTCGP.PopulationSequentialWorkspace(g) for g in graphs] for _ in 1:Threads.nthreads()]
    Threads.@threads :static for j in eachindex(samples)
        ws = workspaces[Threads.threadid()]
        for i in 1:n
            out[i, j] = only(only(UTCGP.evaluate_population_sequential_program(graphs[i], samples[j]...; workspace=ws[i])))
        end
    end
    out
end

function eval_pop(graph, samples, n)
    values = UTCGP.evaluate_population_sequential_program_on_samples(graph, samples)
    out = Matrix{Float64}(undef, n, length(samples))
    for j in eachindex(samples), i in 1:n
        out[i, j] = only(values[j][i])
    end
    out
end


function measure(f; reps=parse(Int,get(ENV,"POP_PROFILE_REPS","3")))
    println("timing kernel"); flush(stdout)
    f() # compile and warm caches
    results=[]
    for _ in 1:reps
        GC.gc()
        t=@timed f()
        push!(results,Dict{String,Any}("seconds"=>t.time,"bytes"=>t.bytes,"gc_seconds"=>t.gctime))
    end
    best=copy(sort(results;by=r->r["seconds"])[cld(reps,2)])
    best["allocated_check"] = @allocated f()
    best["runs"] = results
    println("TIMING_JSON ",JSON.json(best)); flush(stdout)
    best
end
function decode_compile(pop,conf,arch,nc,ml,shared)
    programs,_ = UTCGP._make_decoding(pop,1,conf,arch,nc,ml,shared,(:default_decoding_callback,))
    compile_all(programs,arch,ml,length(pop))
end
function make_children(parent,n,conf,arch,nc,ml,shared)
    p=UTCGP.Population([deepcopy(parent) for _ in 1:n])
    UTCGP.ga_numbered_new_material_mutation_callback(UTCGP.GA_MUTATION_ARGS(p,1,conf,arch,nc,ml,shared))
    p
end
function fastcheck()
    println("clone=",CLONE," revision=",readchomp(`git -C $CLONE rev-parse HEAD`)," Julia=",VERSION," threads=",Threads.nthreads()); flush(stdout)
    Random.seed!(1)
    X,y,_=read_pmlb(joinpath(REPRO_DIR,"POPULATION_datasets/blackbox/606_fri_c2_1000_10.tsv.gz"))
    Xtr,ytr,_,_,_,_=split_scale(X,y,1,0.25,0)
    samples=as_samples(Xtr,parse_constants("0.5,1,2,3,pi"))
    d=length(first(samples))
    arch=modelArchitecture(fill(Float64,d),ones(Int,d),[Float64],[Float64],[1])
    ml=MetaLibrary([Library(UTCGP.get_scalar_sr_bundles();cache_config=UTCGP.NoCacheConfig())])
    nc=nodeConfig(100,1,3,d)
    conf=RunConfGA(1,256,1,1.1,0.1,30)
    shared,parent=make_evolvable_utgenome(arch,ml,nc)
    initialize_genome!(parent); correct_all_nodes!(parent,arch,ml,shared); UTCGP.fix_all_output_nodes!(parent)
    for gen in 1:30
        p=make_children(parent,257,conf,arch,nc,ml,shared)
        g=UTCGP.PopulationSequentialProgram(decode_compile(p,conf,arch,nc,ml,shared))
        P=zeros(257,length(samples))
        UTCGP.evaluate_population_into!(P,g,samples)
        parent=deepcopy(p[argmin(first(population_mse(P,ytr,true)))])
        println("parent generation ",gen); flush(stdout)
    end
    p=make_children(parent,8193,conf,arch,nc,ml,shared)
    cases=[("1+lambda",n,UTCGP.Population(p.pop[1:n]),conf) for n in (257,1025,8193)]
    muconf=RunConfGA(16,256,1,1.1,0.1,1)
    mup=UTCGP.Population([deepcopy(p.pop[mod1(i,257)]) for i in 1:272])
    UTCGP.ga_numbered_new_material_mutation_callback(UTCGP.GA_MUTATION_ARGS(mup,1,muconf,arch,nc,ml,shared))
    push!(cases,("mu+lambda",272,mup,muconf))
    for (label,n,pop,c) in cases
        g=UTCGP.PopulationSequentialProgram(decode_compile(pop,c,arch,nc,ml,shared))
        P=eval_pop(g,samples,n); Q=similar(P)
        w=UTCGP.TypedPopulationWorkspace(g)
        @assert w !== nothing "SR graph unexpectedly fell back"
        UTCGP.evaluate_population_into!(Q,g,samples;workspace=w,check=true)
        @assert all(P[i]===Q[i] for i in eachindex(P))
        scalar=UTCGP.TypedPopulationWorkspace(g;batch_size=1)
        UTCGP.evaluate_population_into!(Q,g,samples;workspace=scalar,check=true)
        baseline=measure(()->eval_pop(g,samples,n))
        fast=measure(()->UTCGP.evaluate_population_into!(Q,g,samples;workspace=w))
        scalarstats=measure(()->UTCGP.evaluate_population_into!(Q,g,samples;workspace=scalar))
        println("FAST_RESULT ",JSON.json(Dict("case"=>label,"N"=>n,"steps"=>length(g.steps),"identity"=>true,"generic"=>baseline,"batch"=>fast,"scalar"=>scalarstats,"speedup"=>baseline["seconds"]/fast["seconds"])))
        flush(stdout)
    end
end
with_logger(ConsoleLogger(stderr,Logging.Warn)) do
    fastcheck()
end
