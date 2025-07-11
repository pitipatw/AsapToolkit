abstract type AbstractPolygonalSection end
abstract type PolygonalSection <: AbstractPolygonalSection end

mutable struct SolidSection <: PolygonalSection
    points::Matrix{Float64}
    points_circular::Matrix{Float64}
    npoints::Int64
    centroid::Vector{Float64}
    area::Float64
    Ix::Float64
    Sx::Float64
    Iy::Float64
    Sy::Float64
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64
    E::Union{Float64, Nothing}


    """
        Default constructor
    """
    function SolidSection(points::Matrix{Float64}, points_circular::Matrix{Float64}, npoints::Int64, centroid::Vector{Float64}, area::Float64, Ix::Float64, Sx::Float64, Iy::Float64, Sy::Float64, xmin::Float64, xmax::Float64, ymin::Float64, ymax::Float64, E::Union{Float64, Nothing})
        new(points, points_circular, npoints, centroid, area, Ix, Sx, Iy, Sy, xmin, xmax, ymin, ymax, E)
    end
    
    """
        SolidSection(points::Matrix{Float64})

    Create a solid section from a [2 × n] matrix of ordered 2D points
    """
    function SolidSection(points::Matrix{Float64}, E = nothing)

        #check 2D
        @assert size(points, 1) == 2 "matrix of point positions must be [2 × n]"

        #remove duplicated end point
        if isapprox(points[:, 1], points[:, end])
            points = points[:, 1:end-1]
        end

        #ensure order of points is counterclockwise
        if !is_counter_clockwise(points)
            points = reverse(points, dims = 2)
        end

        section_properties = compute_section_properties(points)
        
        #make solid
        solid = new(points,
            [points points[:, 1]],
            size(points, 2),
            section_properties.centroid,
            section_properties.area,
            section_properties.Ix,
            section_properties.Sx,
            section_properties.Iy,
            section_properties.Sy,
            section_properties.xmin,
            section_properties.xmax,
            section_properties.ymin,
            section_properties.ymax,
            E
        )

        return solid
    end

    """
        SolidSection(points::Vector{Vector{Float64}})

    Create a solid section from a vector of ordered 2D point vectors
    """
    function SolidSection(points::Vector{Vector{Float64}}, E = nothing)

        points = hcat(points...)

        SolidSection(points)

    end
end

mutable struct VoidSection <: PolygonalSection
    points::Matrix{Float64}
    points_circular::Matrix{Float64}
    npoints::Int64
    centroid::Vector{Float64}
    area::Float64
    Ix::Float64
    Sx::Float64
    Iy::Float64
    Sy::Float64
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64

    """
        Void(points::Matrix{Float64})

    Create a void section from a [2 × n] matrix of ordered 2D points
    """
    function VoidSection(points::Matrix{Float64})

        #check 2D
        @assert size(points, 1) == 2 "matrix of point positions must be [2 × n]"

        #remove duplicated points
        if isapprox(points[:, 1], points[:, end])
            points = points[:, 1:end-1]
        end

        #ensure order of points is clockwise
        if is_counter_clockwise(points)
            points = reverse(points, dims = 2)
        end

        #populate section properties
        
        section_properties = compute_section_properties(points)

        void = new(points,
            [points points[:, 1]],
            size(points, 2),
            section_properties.centroid,
            -section_properties.area,
            -section_properties.Ix,
            -section_properties.Sx,
            -section_properties.Iy,
            -section_properties.Sy,
            section_properties.xmin,
            section_properties.xmax,
            section_properties.ymin,
            section_properties.ymax
        )

        return void

    end

    function VoidSection(points::Vector{Vector{Float64}})

        points = hcat(points...)

        Void(points)

    end

    function VoidSection(section::SolidSection)

        new(
            section.points, 
            section.points_circular, 
            section.npoints, 
            section.centroid, 
            -section.area,
            -section.Ix,
            -section.Sx,
            -section.Iy,
            -section.Sy,
            section.xmin,
            section.xmax,
            section.ymin,
            section.ymax
        )

    end
end

struct CompoundSection <: AbstractPolygonalSection
    solids::Vector{SolidSection}
    voids::Vector{VoidSection}
    centroid::Vector{Float64}
    area::Float64
    Ix::Float64
    Sx::Float64
    Iy::Float64
    Sy::Float64
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64

    function CompoundSection(sections::Vector{SolidSection})

        #get centroid and area
        A = 0.
        centroid = [0., 0.]

        for section in sections
            A += section.area
            centroid += section.area * section.centroid
        end

        centroid /= A

        Cx, Cy = centroid

        #get section properties
        Ix = 0.
        Iy = 0.

        for section in sections
            Ix += section.Ix + section.area * (centroid[2] - section.centroid[2])^2
            Iy += section.Iy + section.area * (centroid[1] - section.centroid[1])^2
        end

        #organize sections
        
        # Separate the input list into solids and voids without mutation
        solids = filter(s -> isa(s, SolidSection), sections)
        voids  = filter(s -> !isa(s, SolidSection), sections)

        xmin = minimum(getproperty.(sections, :xmin))
        xmax = maximum(getproperty.(sections, :xmax))
        ymin = minimum(getproperty.(sections, :ymin))
        ymax = maximum(getproperty.(sections, :ymax))

        Sx = Ix / maximum(abs.([ymin, ymax] .- Cy))
        Sy = Iy / maximum(abs.([xmin, xmax] .- Cx))

        return new(solids, voids, centroid, A, Ix, Sx, Iy, Sy, xmin, xmax, ymin, ymax)
    end
end

struct OffsetSection
    section::AbstractPolygonalSection
    center_of_rotation::Vector{Float64}
    Ix::Float64
    Sx::Float64
    Iy::Float64
    Sy::Float64

    """
        OffsetSection(section::AbstractPolygonalSection, center_of_rotation::Vector{<:Real})

    Generate a section with a center of rotation that is not coincident with the centroid of the section
    """
    function OffsetSection(section::AbstractPolygonalSection, center_of_rotation::Vector{<:Real})

        @assert length(center_of_rotation) == 2 "center_of_rotation must be a 2D vector"

        dx, dy = section.centroid - center_of_rotation

        Ix = section.Ix + section.area * dy^2
        Iy = section.Iy + section.area * dx^2

        x_max_critical = maximum(abs.([section.xmin, section.xmax] .- center_of_rotation[1]))
        y_max_critical = maximum(abs.([section.ymin, section.ymax] .- center_of_rotation[2]))

        Sx = Ix / y_max_critical
        Sy = Iy / x_max_critical

        return new(section, center_of_rotation, Ix, Sx, Iy, Sy)
    end

end