abstract type AbstractMonotonizedSymmetricConnectivityModel end

@inline (mdl::AbstractMonotonizedSymmetricConnectivityModel)(n_vertices, n_over_pins, n_dia_nets, k) = mdl(n_vertices, n_over_pins, n_dia_nets)

struct AffineMonotonizedSymmetricConnectivityModel{Tv} <: AbstractMonotonizedSymmetricConnectivityModel
    α::Tv
    β_vertex::Tv
    β_over_pin::Tv
    β_dia_net::Tv
    Δ_pins::Tv
end

function AffineMonotonizedSymmetricConnectivityModel(; α = false, β_vertex = false, β_over_pin = false, β_dia_net = false, Δ_pins = false)
    AffineMonotonizedSymmetricConnectivityModel(promote(α, β_vertex, β_over_pin, β_dia_net, Δ_pins)...)
end

function AffineMonotonizedSymmetricConnectivityModel(mdl::AffineSymmetricConnectivityModel{Tv}) where {Tv}
    α = mdl.α
    β_dia_net = mdl.β_remote_net
    β_over_pin = mdl.β_pin
    if mdl.β_vertex < mdl.β_remote_net
        Δ_pins = cld(mdl.β_remote_net - mdl.β_vertex, mdl.β_pin)
        β_vertex = zero(Tv)
    else
        Δ_pins = 0
        β_vertex = mdl.β_vertex - mdl.β_remote_net
    end
    return AffineMonotonizedSymmetricConnectivityModel(α, β_vertex, β_over_pin, β_dia_net, Δ_pins)
end

@inline cost_type(::Type{AffineMonotonizedSymmetricConnectivityModel{Tv}}) where {Tv} = Tv

(mdl::AffineMonotonizedSymmetricConnectivityModel)(n_vertices, n_over_pins, n_dia_nets) = mdl.α + n_vertices * mdl.β_vertex + n_over_pins * mdl.β_over_pin + n_dia_nets * mdl.β_dia_net

function bound_stripe(A::SparseMatrixCSC, K, ocl::AbstractOracleCost{<:AffineMonotonizedSymmetricConnectivityModel})
    m, n = size(A)
    @assert m == n
    N = nnz(A)
    mdl = oracle_model(ocl)
    @assert mdl.β_vertex >= 0
    @assert mdl.β_over_pin >= 0
    @assert mdl.β_dia_net >= 0
    c_hi = ocl(1, n + 1)
    c_lo = mdl.α + fld(c_hi - mdl.α, K)
    return (c_lo, c_hi)
end



function bound_stripe(A::SparseMatrixCSC, K, mdl::AffineMonotonizedSymmetricConnectivityModel)
    @inbounds begin
        @assert mdl.β_vertex >= 0
        @assert mdl.β_over_pin >= 0
        @assert mdl.β_dia_net >= 0
        m, n = size(A)
        @assert m == n
        N = nnz(A)
        n_over_pins = 0
        for j = 1:n
            n_over_pins += max(A.colptr[j + 1] - A.colptr[j] - mdl.Δ_pins, 0)
        end
        c_hi = mdl.α + mdl.β_vertex * n + mdl.β_over_pin * n_over_pins + mdl.β_dia_net * m
        c_lo = mdl.α + fld(c_hi - mdl.α, K)
        return (c_lo, c_hi)
    end
end

struct MonotonizedSymmetricConnectivityOracle{Ti, DiaNet, Mdl} <: AbstractOracleCost{Mdl}
    overpos::Vector{Ti}
    dianet::DiaNet
    mdl::Mdl
end

oracle_model(ocl::MonotonizedSymmetricConnectivityOracle) = ocl.mdl


function oracle_stripe(hint::AbstractHint, mdl::AbstractMonotonizedSymmetricConnectivityModel, A::SparseMatrixCSC{Tv, Ti}; net=nothing, adj_A=nothing, kwargs...) where {Tv, Ti}
    @inbounds begin
        m, n = size(A)
        @assert m == n
        N = nnz(A)
        overpos = undefs(eltype(A.colptr), n + 1)
        overpos[1] = 1
        for j = 1:n
            overpos[j + 1] = overpos[j] + max(A.colptr[j + 1] - A.colptr[j] - mdl.Δ_pins, 0)
        end

        dianet = dianetcount(hint, A; kwargs...)

        return MonotonizedSymmetricConnectivityOracle(overpos, dianet, mdl)
    end
end

function bound_stripe(A::SparseMatrixCSC, K, ocl::MonotonizedSymmetricConnectivityOracle{<:Any, <:Any, <:AffineMonotonizedSymmetricConnectivityModel})
    m, n = size(A)
    @assert m == n
    N = nnz(A)
    mdl = oracle_model(ocl)
    @assert mdl.β_vertex >= 0
    @assert mdl.β_over_pin >= 0
    @assert mdl.β_dia_net >= 0
    c_hi = mdl.α + mdl.β_vertex * n + mdl.β_over_pin * (ocl.overpos[end] - ocl.overpos[1]) + mdl.β_dia_net * m
    c_lo = mdl.α + fld(c_hi - mdl.α, K)
    return (c_lo, c_hi)
end

@inline function (cst::MonotonizedSymmetricConnectivityOracle{Ti, Mdl})(j::Ti, j′::Ti, k...) where {Ti, Mdl}
    @inbounds begin
        w = cst.overpos[j′] - cst.overpos[j]
        d = cst.dianet[j, j′]
        return cst.mdl(j′ - j, w, d, k...)
    end
end

@inline function (stp::Step{Ocl})(_j, _j′, _k...) where {Ti, Mdl, Ocl <: MonotonizedSymmetricConnectivityOracle{Ti, Mdl}}
    @inbounds begin
        cst = stp.ocl
        j = destep(_j)
        j′ = destep(_j′)
        k = maptuple(destep, _k...)
        w = cst.overpos[j′] - cst.overpos[j]
        d = Step(cst.dianet)(_j, _j′)
        return cst.mdl(j′ - j, w, d, k...)
    end
end