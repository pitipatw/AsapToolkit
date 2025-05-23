
"""
Accumlate the internal forces cause by a given load to the current element
"""
function accumulate_force!(load::LineLoad, 
    xvals::Vector{Float64}, 
    P::Vector{Float64},
    My::Vector{Float64}, 
    Vy::Vector{Float64}, 
    Mz::Vector{Float64}, 
    Vz::Vector{Float64})

    R = load.element.R[1:3, 1:3]
    L = load.element.length

    # distributed load magnitudes in LCS
    wx, wy, wz = (R  * load.value) .* [1, -1, -1]

    P .+= [PLine(wx, L, x) for x in xvals]

    My .+= [MLine(load.element, wy, L, x) for x in xvals]
    Vy .+= [VLine(load.element, wy, L, x) for x in xvals]

    Mz .+= [MLine(load.element, wz, L, x) for x in xvals]
    Vz .+= [VLine(load.element, wz, L, x) for x in xvals]
end

"""
Accumlate the internal forces cause by a given load to the current element
"""
function accumulate_force!(load::PointLoad, 
    xvals::Vector{Float64}, 
    P::Vector{Float64},
    My::Vector{Float64}, 
    Vy::Vector{Float64}, 
    Mz::Vector{Float64}, 
    Vz::Vector{Float64})

    R = load.element.R[1:3, 1:3]
    L = load.element.length
    frac = load.position

    # distributed load magnitudes in LCS
    px, py, pz = (R  * load.value) .* [1, -1, -1]

    P .+= [PPoint(px, L, x, frac) for x in xvals]

    My .+= [MPoint(load.element, py, L, x, frac) for x in xvals]
    Vy .+= [VPoint(load.element, py, L, x, frac) for x in xvals]

    Mz .+= [MPoint(load.element, pz, L, x, frac) for x in xvals]
    Vz .+= [VPoint(load.element, pz, L, x, frac) for x in xvals]
end

"""
Store the internal force results for a given element
"""
struct InternalForces
    element::Element
    resolution::Integer
    x::Vector{Float64}
    P::Vector{Float64}
    My::Vector{Float64}
    Vy::Vector{Float64}
    Mz::Vector{Float64}
    Vz::Vector{Float64}
end


"""
Internal force sampling for an element 
"""
function InternalForces(element::Element, model::Model; resolution = 20)
    
    #beam information
    release = element.release
    L = element.length

    #discretization
    xinc = collect(range(0, L, resolution))

    #end node information
    uglobal = [element.nodeStart.displacement; element.nodeEnd.displacement]
    
    # end forces that are relevant to the given element/release condition
    Flocal = (element.R * element.K * uglobal) .* release2DOF[release]

    # shear/moment acting at the *starting* point of an element in LCS
    Pstart, Vystart, Mystart, Vzstart, Mzstart = Flocal[[1, 2, 6, 3, 5]] .* [-1, 1, 1, 1, -1]

    # initialize internal force vectors
    P = repeat([Pstart], resolution)
    My = Vystart .* xinc .- Mystart
    Vy = zero(My) .+ Vystart
    Mz = Vzstart .* xinc .- Mzstart
    Vz = zero(Mz) .+ Vzstart

    # accumulate loads
    for load in model.loads[element.loadIDs]
        accumulate_force!(load,
            xinc,
            P,
            My,
            Vy,
            Mz,
            Vz)  
    end

    return InternalForces(element, resolution, xinc, P, My, Vy, Mz, Vz)
end

"""
    InternalForces(element::Element, loads::Vector{<:ElementLoad}; resolution = 20)

Get internal force results for a given element from a set of loads
"""
function InternalForces(element::Element, loads::Vector{<:Asap.ElementLoad}; resolution = 20)
    
    #beam information
    dofs = etype2DOF[typeof(element)]
    L = element.length

    #discretization
    xinc = collect(range(0, L, resolution))

    #end node information
    uglobal = [element.nodeStart.displacement; element.nodeEnd.displacement]
    
    # end forces that are relevant to the given element/release condition
    Flocal = (element.R * element.K * uglobal) .* dofs

    # shear/moment acting at the *starting* point of an element in LCS
    Pstart, Vystart, Mystart, Vzstart, Mzstart = Flocal[[1, 2, 6, 3, 5]] .* [-1, 1, 1, 1, -1]

    # initialize internal force vectors
    P = repeat([Pstart], resolution)
    My = Vystart .* xinc .- Mystart
    Vy = zero(My) .+ Vystart
    Mz = Vzstart .* xinc .- Mzstart
    Vz = zero(Mz) .+ Vzstart

    # accumulate loads
    for load in loads
        accumulate_force!(load,
            xinc,
            P,
            My,
            Vy,
            Mz,
            Vz)  
    end

    return InternalForces(element, resolution, xinc, P, My, Vy, Mz, Vz)
end


function get_elemental_loads(model::Model)

    element_to_loadids = [Int64[] for _ in 1:model.nElements]
    for load in model.loads
        push!(element_to_loadids[load.element.elementID], load.loadID)
    end

    return element_to_loadids

end

"""
    InternalForces(element::Vector{<:FrameElement}, model::Model; resolution = 20)

Get internal force results for a group of ordered elements that form a single physical element
"""
function InternalForces(elements::Vector{<:Asap.FrameElement}, model::Model; resolution = 20)
    
    xstore = Vector{Float64}()
    pstore = Vector{Float64}()
    mystore = Vector{Float64}()
    vystore = Vector{Float64}()
    mzstore = Vector{Float64}()
    vzstore = Vector{Float64}()

    resolution = Int(round(resolution / length(elements)))

    element_load_ids = get_elemental_loads(model)

    #beam information
    for (element, loadids) in zip(elements, element_load_ids)

        dofs = etype2DOF[typeof(element)]
        L = element.length

        #discretization
        xinc = collect(range(0, L, max(resolution, 2)))

        #end node information
        uglobal = [element.nodeStart.displacement; element.nodeEnd.displacement]
        
        # end forces that are relevant to the given element/release condition
        Flocal = (element.R * element.K * uglobal) .* dofs

        # shear/moment acting at the *starting* point of an element in LCS
        Pstart, Vystart, Mystart, Vzstart, Mzstart = Flocal[[1, 2, 6, 3, 5]] .* [-1, 1, 1, 1, -1]

        # initialize internal force vectors
        P = repeat([Pstart], resolution)
        My = Vystart .* xinc .- Mystart
        Vy = zero(My) .+ Vystart
        Mz = Vzstart .* xinc .- Mzstart
        Vz = zero(Mz) .+ Vzstart

        # accumulate loads
        for load in model.loads[loadids]
            accumulate_force!(load,
                xinc,
                P,
                My,
                Vy,
                Mz,
                Vz)  
        end

        if isempty(xstore)
            xstore = [xstore; xinc]
        else
            xstore = [xstore; xstore[end] .+ xinc]
        end

        pstore = [pstore; P]
        mystore = [mystore; My]
        vystore = [vystore; Vy]
        mzstore = [mzstore; Mz]
        vzstore = [vzstore; Vz]

    end

    return InternalForces(elements[1], resolution, xstore, pstore, mystore, vystore, mzstore, vzstore)
end



"""
    forces(model::Model, increment::Real)

Get the internal forces of all elements in a model.

- `model::Model` structural model whose elements are analyzed
- `increment::Real` distance between sampling points along the element
"""
function InternalForces(model::Model, increment::Real)

    results = Vector{InternalForces}()

    loadids = get_elemental_loads(model)

    for (element, loadset) in zip(model.elements, loadids)
    
        n = max(Int(round(element.length / increment)), 2)

        push!(results, InternalForces(element, model.loads[loadset]; resolution = n))
    end

    return results
end

struct ForceEnvelopes
    element::Element
    resolution::Integer
    x::Vector{Float64}
    Plow::Vector{Float64}
    Phigh::Vector{Float64}
    Mylow::Vector{Float64}
    Myhigh::Vector{Float64}
    Vylow::Vector{Float64}
    Vyhigh::Vector{Float64}
    Mzlow::Vector{Float64}
    Mzhigh::Vector{Float64}
    Vzlow::Vector{Float64}
    Vzhigh::Vector{Float64}
end

"""
    load_envelopes(model::Model, loads::Vector{Vector{<:AbstractLoad}})

Get the high/low internal forces for a series of external loads
"""
function load_envelopes(model::Model, loads::Vector{Vector{<:Asap.AbstractLoad}}, increment::Real)
    #
    envelopes = Vector{ForceEnvelopes}()

    #collector of force results
    forceresults = Vector{Vector{InternalForces}}()

    # perform analysis
    for load in loads
        solve!(model, load)
        push!(forceresults, forces(model, increment))
    end

    # number of actual elements
    n = length(first(forceresults))

    # for each element
    for i = 1:n
        e = first(forceresults)[i].element
        res = first(forceresults)[i].resolution
        x = first(forceresults)[i].x

        P = hcat(getproperty.(getindex.(forceresults, i), :P)...)
        My = hcat(getproperty.(getindex.(forceresults, i), :My)...)
        Vy = hcat(getproperty.(getindex.(forceresults, i), :Vy)...)
        Mz = hcat(getproperty.(getindex.(forceresults, i), :Mz)...)
        Vz = hcat(getproperty.(getindex.(forceresults, i), :Vz)...)

        Prange = extrema.(eachrow(P))
        Myrange = extrema.(eachrow(My))
        Vyrange = extrema.(eachrow(Vy))
        Mzrange = extrema.(eachrow(Mz))
        Vzrange = extrema.(eachrow(Vz))

        envelope = ForceEnvelopes(e,
            res,
            x,
            getindex.(Prange, 1),
            getindex.(Prange, 2),
            getindex.(Myrange, 1),
            getindex.(Myrange, 2),
            getindex.(Vyrange, 1),
            getindex.(Vyrange, 2),
            getindex.(Mzrange, 1),
            getindex.(Mzrange, 2),
            getindex.(Vzrange, 1),
            getindex.(Vzrange, 2))

        push!(envelopes, envelope)
    end

    return envelopes
end