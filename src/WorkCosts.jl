abstract type AbstractWorkCost end

@inline (mdl::AbstractWorkCost)(n_vertices, n_pins, k) = mdl(n_vertices, n_pins)

struct AffineWorkModel{Tv} <: AbstractWorkCost
    α::Tv
    β_vertex::Tv
    β_pin::Tv
end

function AffineWorkModel(; α = false, β_vertex = false, β_pin = false)
    AffineWorkModel(promote(α, β_vertex, β_pin)...)
end

@inline cost_type(::Type{AffineWorkModel{Tv}}) where {Tv} = Tv

(mdl::AffineWorkModel)(n_vertices, n_pins) = mdl.α + n_vertices * mdl.β_vertex + n_pins * mdl.β_pin

struct WorkOracle{Ti, Mdl <: AbstractWorkCost} <: AbstractOracleCost{Mdl}
    pos::Vector{Ti}
    mdl::Mdl
end

oracle_model(ocl::WorkOracle) = ocl.mdl

function oracle_stripe(hint::AbstractHint, mdl::AbstractWorkCost, A::SparseMatrixCSC; kwargs...)
    return WorkOracle(A.colptr, mdl)
end

@inline function (cst::WorkOracle{Ti, Mdl})(j::Ti, j′::Ti, k...) where {Ti, Mdl}
    @inbounds begin
        w = cst.pos[j′] - cst.pos[j]
        return cst.mdl(j′ - j, w, k...)
    end
end

bound_stripe(A::SparseMatrixCSC, K, ocl::WorkOracle{<:Any, <:AffineWorkModel}) = 
    bound_stripe(A, K, oracle_model(ocl))
function bound_stripe(A::SparseMatrixCSC, K, mdl::AffineWorkModel)
    m, n = size(A)
    N = nnz(A)
    c_lo = mdl.α + fld(mdl.β_vertex * n + mdl.β_pin * N, K)
    if mdl.β_vertex ≥ 0 && mdl.β_pin ≥ 0
        c_hi = mdl.α + mdl.β_vertex * n + mdl.β_pin * N
    elseif mdl.β_vertex ≤ 0 && mdl.β_pin ≤ 0
        c_hi = mdl.α 
    else
        @assert false
    end
    return (c_lo, c_hi)
end

function compute_objective(g::G, A::SparseMatrixCSC, Π::SplitPartition, mdl::AbstractWorkCost) where {G}
    cst = objective_identity(g, cost_type(mdl))
    for k = 1:Π.K
        j = Π.spl[k]
        j′ = Π.spl[k + 1]
        cst = g(cst, mdl(j′ - j, A.colptr[j′] - A.colptr[j], k))
    end
    return cst
end

function compute_objective(g::G, A::SparseMatrixCSC, Π::DomainPartition, mdl::AbstractWorkCost) where {G}
    cst = objective_identity(g, cost_type(mdl))
    for k = 1:Π.K
        s = Π.spl[k]
        s′ = Π.spl[k + 1]
        n_vertices = s′ - s
        n_pins = 0
        for _s = s : s′ - 1
            j = Π.prm[_s]
            n_pins += A.colptr[j + 1] - A.colptr[j]
        end
        cst = g(cst, mdl(n_vertices, n_pins, k))
    end
    return cst
end

function compute_objective(g, A::SparseMatrixCSC, Π::MapPartition, mdl::AbstractWorkCost)
    return compute_objective(g, A, convert(DomainPartition, Π), mdl)
end