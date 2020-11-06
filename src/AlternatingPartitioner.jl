struct DisjointPartitioner{Mtd, Mtd′}
    mtd::Mtd
    mtd′::Mtd′
end

function partition_plaid(A::SparseMatrixCSC, k, method::DisjointPartitioner; kwargs...)
    Φ = partition_stripe(A, k, method.mtd; kwargs...)
    Π = partition_stripe(PermutedDimsArray(A, (2, 1)), k, method.mtd′, Φ; kwargs...)
    return (Π, Φ)
end

struct AlternatingPartitioner{Mtds}
    mtds::Mtds
end

AlternatingPartitioner(mtds...) = AlternatingPartitioner{typeof(mtds)}(mtds)

function partition_plaid(A::SparseMatrixCSC, k, method::AlternatingPartitioner; adj_A = nothing, kwargs...)
    if adj_A === nothing
        adj_A = adjointpattern(A)
    end
    Φ = partition_stripe(A, k, method.mtds[1]; adj_A=adj_A, kwargs...)
    Π = partition_stripe(adj_A, k, method.mtds[2], Φ; adj_A=A, kwargs...)
    for (i, mtd) in enumerate(method.mtds[3:end])
        if isodd(i)
            Φ = partition_stripe(A, k, mtd, Π; adj_A=adj_A, kwargs...)
        else
            Π = partition_stripe(adj_A, k, mtd, Φ; adj_A=A, kwargs...)
        end
    end
    return (Π, Φ)
end

struct AlternatingNetPartitioner{Mtds}
    mtds::Mtds
end

AlternatingNetPartitioner(mtds...) = AlternatingNetPartitioner{typeof(mtds)}(mtds)

function partition_plaid(A::SparseMatrixCSC, k, method::AlternatingNetPartitioner; adj_A = nothing, net = nothing, kwargs...)
    if adj_A === nothing
        adj_A = adjointpattern(A)
    end
    if net === nothing
        net = rownetcount(A; kwargs...)
    end
    Φ = partition_stripe(A, k, method.mtds[1]; net=net, adj_A=adj_A, kwargs...)
    Π = partition_stripe(adj_A, k, method.mtds[2], Φ; adj_A=A, kwargs...)
    for (i, mtd) in enumerate(method.mtds[3:end])
        if isodd(i)
            Φ = partition_stripe(A, k, mtd, Π; net=net, adj_A=adj_A, kwargs...)
        else
            Π = partition_stripe(adj_A, k, mtd, Φ; adj_A=A, adj_net = net, kwargs...)
        end
    end
    return (Π, Φ)
end