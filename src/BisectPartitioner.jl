struct BisectPartitioner{F, T}
    f::F
    ϵ::T
end

function partition_stripe(A::SparseMatrixCSC{Tv, Ti}, K, method::BisectPartitioner, args...; kwargs...) where {Tv, Ti}
    @inbounds begin 
        (m, n) = size(A)
        f = oracle_stripe(method.f, A, K, args...; kwargs...)
        ϵ = method.ϵ

        #=
            search returns the largest j′ such that
            f(j, j′) <= c
        =#
        @inline function search(j, j′_lo, j′_hi, k, c)
            j′_lo = max(j, j′_lo)
            while j′_lo <= j′_hi
                j′ = fld2(j′_lo + j′_hi)
                if f(j, j′, k) <= c
                    j′_lo = j′ + 1
                else # f(j, j′) > c
                    j′_hi = j′ - 1
                end
            end
            return j′_hi
        end

        spl_lo = ones(Int, K + 1)

        spl_hi = fill(n + 1, K + 1)
        spl_hi[1] = 1

        spl = undefs(Int, K + 1)
        spl[1] = 1

        c_lo, c_hi = bound_stripe(A, K, args..., f)./1

        while c_lo * (1 + ϵ) < c_hi
            c = (c_lo + c_hi) / 2
            spl[1] = 1
            chk = true
            for k = 1 : K
                spl[k + 1] = search(spl[k], spl_lo[k + 1], spl_hi[k + 1], k, c)
                if spl[k + 1] < max(spl[k], spl_lo[k + 1])
                    chk = false
                    spl[k + 1 : end] .= spl_lo[k + 1 : end]
                    break
                end
            end
            if chk && spl[end] == n + 1 #yes, we can achieve spl[k + 1] at the cost of c.
                c_hi = c #thus, we have a lower achievable cost for c_hi
                spl_hi .= spl #record the split points which achieved c_hi
            else #no we cannot achieve spl[k + 1] at the cost of c.
                c_lo = c #since c is not achievable, no cost below c can be achievable
                spl_lo .= spl #these split points cannot achieve an improvement on c_hi
            end
        end
        return SplitPartition(K, spl_hi)
    end
end

struct FlipBisectPartitioner{F, T}
    f::F
    ϵ::T
end

function partition_stripe(A::SparseMatrixCSC{Tv, Ti}, K, method::FlipBisectPartitioner, args...; kwargs...) where {Tv, Ti}
    @inbounds begin 
        (m, n) = size(A)
        f = oracle_stripe(method.f, A, K, args...; kwargs...)
        ϵ = method.ϵ

        #=
            search returns the largest j′ such that
            f(j, j′) <= c. returns j′_hi + 1 if no
            such j′ can be found
        =#
        @inline function search(j, j′_lo, j′_hi, k, c)
            j′_lo = max(j, j′_lo)
            @assert j′_lo <= j′_hi
            while j′_lo <= j′_hi
                j′ = fld2(j′_lo + j′_hi)
                if f(j, j′, k) <= c
                    j′_hi = j′ - 1
                else # f(j, j′) > c
                    j′_lo = j′ + 1
                end
            end
            return j′_lo
        end

        spl_lo = ones(Int, K + 1)

        spl_hi = fill(n + 1, K + 1)
        spl_hi[1] = 1

        spl = undefs(Int, K + 1)
        spl[1] = 1

        c_lo, c_hi = bound_stripe(A, K, args..., f) ./ 1

        while c_lo * (1 + ϵ) < c_hi
            c = (c_lo + c_hi) / 2
            spl[1] = 1
            chk = true
            for k = 1 : K
                spl[k + 1] = search(spl[k], spl_lo[k + 1], spl_hi[k + 1], k, c)
                if spl[k + 1] > spl_hi[k + 1]
                    chk = false
                    spl[k + 1 : end] .= spl_hi[k + 1 : end]
                    break
                end
            end
            if chk #yes, we can achieve spl[k + 1] at the cost of c.
                c_hi = c #thus, we have a lower achievable cost for c_hi
                spl_lo .= spl #record the split points which achieved c_hi
            else #no we cannot achieve spl[k + 1] at the cost of c.
                c_lo = c #since c is not achievable, no cost below c can be achievable
                spl_hi .= spl #these split points cannot achieve an improvement on c_hi
            end
        end
        spl_lo[K + 1] = n + 1
        return SplitPartition(K, spl_lo)
    end
end