using Test, Random
using ImageCore: N0f8, N0f16

# Discover bindings in MAGE and its library modules, including experimental
# bundles that are intentionally not exported from MAGE.
function _image_out_bundles()
    found = Dict{Symbol,Any}()
    modules = Module[MAGE]
    for name in names(MAGE; all=true)
        isdefined(MAGE,name) || continue
        value = getfield(MAGE,name)
        value isa Module && parentmodule(value) === MAGE && push!(modules,value)
    end
    for mod in modules, name in names(mod; all=true)
        text = string(name)
        occursin("bundle_",text) && occursin("factory",text) || continue
        occursin("image",lowercase(text)) || name === :bundle_element_conditional_factory || continue
        isdefined(mod,name) || continue
        bundle = getfield(mod,name)
        bundle isa MAGE.FunctionBundle || continue
        found[name] = bundle
    end
    return sort!(collect(found); by=p -> string(first(p)))
end

# Called in the newest world after factories install their methods.
function _check_image_out_method(fn,args,label)
    argtypes = typeof(args)
    @test hasmethod(fn,argtypes,(:out,))
    hasmethod(fn,argtypes,(:out,)) || return
    expected = fn(args...)
    @test expected isa SImageND
    expected isa SImageND || return
    rt = Core.Compiler.return_type(fn,argtypes)
    @test rt === typeof(expected)
    out = deepcopy(expected)
    keyword_types = Tuple{typeof((;out)),typeof(fn),typeof.(args)...}
    @test Core.Compiler.return_type(Core.kwcall,keyword_types) === typeof(expected)
    # Test both extreme garbage values: early return paths must also overwrite.
    for value in (zero(eltype(out.img)),one(eltype(out.img)),nothing)
        if value === nothing
            out.img .= eltype(out.img).(rand(MersenneTwister(31),Bool,size(out.img)))
        else
            fill!(out.img,value)
        end
        result = fn(args...;out)
        @test result === out
        @test typeof(result) === typeof(expected)
        @test all(i -> isequal(result.img[i],expected.img[i]),eachindex(expected.img))
    end
end
function _check_image_out_factory(fn,images,label)
    # The decoder consumes fixed arguments; framework Varargs do not count.
    candidates = (images...,0.4,2)
    covered = Set{Method}()
    cases = Set{Tuple{Method,Type}}()
    max_arity = maximum(method.nargs-2 for method in methods(fn))
    for n in 0:max_arity, args in Iterators.product(ntuple(_ -> candidates,n)...)
        hasmethod(fn,typeof(args)) || continue
        method = which(fn,typeof(args))
        fixed = method.nargs-2
        fixed == n || continue
        # A polymorphic method may have distinct intensity/binary/segment paths.
        # Exercise each concrete first-input type, not only its first match.
        case = (method,isempty(args) ? Nothing : typeof(first(args)))
        case in cases && continue
        push!(cases,case)
        push!(covered,method)
        @testset "$label / $(method.sig)" begin
            _check_image_out_method(fn,args,(label,typeof(args)))
        end
    end
    for method in methods(fn)
        @test method in covered
    end
    @test !isempty(covered)
end

@testset "Every image bundle: out keyword, inference, full overwrite" begin
    rng = MersenneTwister(927)
    bundles = _image_out_bundles()
    @test length(bundles) >= 47
    # Both fixed-point storage types used in inference tests; binary/segment
    # factories are deduplicated because their types do not depend on storage.
    visited = Set{Tuple{Symbol,Symbol,DataType}}()
    for storage in (N0f8,N0f16)
        i2 = SImageND(IntensityPixel{storage}.(rand(rng,16,16)))
        # A valid connected foreground, avoiding degenerate graph/segmentation inputs.
        b2 = SImageND(BinaryPixel.([3<=r<=13 && 4<=c<=12 for r in 1:16,c in 1:16]))
        s2 = SImageND(SegmentPixel{Int}.([r<=8 ? 1 : 2 for r in 1:16,c in 1:16]))
        rgb = SImageND(IntensityPixel{storage}.(rand(rng,16,16,3)))
        brgb = SImageND(BinaryPixel.(rand(rng,Bool,16,16,3)))
        v = SImageND(IntensityPixel{storage}.(rand(rng,16,16,16)))
        bv = SImageND(BinaryPixel.(rand(rng,Bool,16,16,16)))
        images = (i2,b2,s2,rgb,brgb,v,bv)
        for (name,bundle) in bundles
            text = string(name)
            outputs = if occursin("image2DIntensity",text)
                (i2,)
            elseif occursin("image2DBinary",text)
                (b2,)
            elseif occursin("image2DSegment",text)
                (s2,)
            elseif occursin("image3DIntensity",text)
                occursin("volume",text) ? (v,) : (rgb,)
            elseif occursin("image3DBinary",text)
                (bv,)
            else
                (i2,b2,s2) # generic masks and image conditional factory
            end
            for image in outputs, wrapper in bundle
                key = (name,wrapper.name,typeof(image))
                key in visited && continue
                push!(visited,key)
                @testset "$name / $(wrapper.name) / $(typeof(image))" begin
                    @test applicable(wrapper.fn,typeof(image))
                    fn = wrapper.fn(typeof(image))
                    Base.invokelatest(_check_image_out_factory,fn,images,(name,wrapper.name,typeof(image)))
                end
            end
        end
    end
end
