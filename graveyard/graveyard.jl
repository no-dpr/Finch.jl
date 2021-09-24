module FiberArrays

abstract type AbstractFiberArray{T, F, N} <: AbstractArray{T, N} end

struct DenseFiberArray{T, F, N}
    
end

end

abstract type AbstractFiberArray{T, N, V} <: AbstractArray{T, N}

Base.size(arr::AbstractFiberArray{T, N}) = _size(arr)

_size(arr) = (dimension(arr), _size(value(arr))...)

Base.getindex(arr::AbstractFiberArray{T, N}, inds::Vararg{N}) where {T, N} = _getindex(arr, inds...)

_getindex(arr::AbstractFiberArray, i, tail...) = getfiber(child(arr), )[tail...]




struct DenseMode{T, N, V}
    I::Int
    v::V
end

dimension(mode::DenseMode) = mode.I

struct DenseFiberArray{T, V} <: AbstractVector{T, N}
    j::Int
    v::V
end

getfiber(arr::DenseFiberArray, j) = DenseFiber(j, arr)

Base.size(vec::DenseFiber) = vec.I

Base.getindex(vec::DenseFiber, i) = (vec.j - 1) * vec.I + i


struct SparseMode{Ti}
    I::Int
    pos::Vector{Ti}
    idx::Vector{Ti}
end

Base.size(mode::SparseMode) = (mode.I,)




struct Run{Tv, Ti}
    arg
end

struct Runs{T}
    arg::T
end

function iterate(rns::Runs{SparseFiber{Tv, Ti}}) where {Tv, Ti}
    return iterate(rns, Ti(1), Ti(1))
end

function iterate(rns::Runs{SparseFiber{Tv, Ti}}, i::Ti, q::Ti) where {Tv, Ti}
    fbr = rns.arg
    idx = fbr.idx
    if q < Q
        i′ = idx[q]
        return (Spike{Tv, Ti}(i + Ti(1), i′, val[q]), i′, q + Ti(1))
    elseif q == Q
        i = idx[q]
        return (Zero{Tv, Ti}(i + Ti(1), i′), i′, q + Ti(1))
    else
        return nothing
    end
end

function execute(::Typeof{+}, a::Spike, b::Spike)
    if a.i′ == b.i′
        return (Spike{Tv, Ti}(a.i′, a.v + b.v), a.i′)
    elseif a.i′ < b.i′
        return (Spike{Tv, Ti}(a.i′, a.v), a.i′)
    elseif a.i′ > b.i′
        return (Spike{Tv, Ti}(a.i′, b.v), b.i′)
    end
end

function execute(::Typeof{*}, a::Spike, b::DenseFiber)
    return (Spike{Tv, Ti}(a.i′, a.v + b.v[i]), a.i′)
end

function coiterate(runs, runs, runs)
    run1, state1, run2, run3 = iterate(runs1), iterate(runs2), iterate(runs3)
    i = 1
    while i < I
        (res, i′) = execute(run1 & run2) | run3
        if i′ < lastindex(run1)
            run1 = truncate(run1, i′)
        else
            run1 = iterate(run1, state1)
        end
        if i′ < lastindex(run2)
            run2 = truncate(run2, i′)
        else
            run2 = iterate(run2, state2)
        end
        if i′ < lastindex(run3)
            run3 = truncate(run3, i′)
        else
            run3 = iterate(run3, state3)
        end
        i = i′
    end
end


struct SparseVectorSplitIterator
    prev_pos
    vec
end

IteratorStyle(itr::SparseVectorSplitIterator) = SplitStyle()

setup(itr::SparseVectorSplitIterator) = :(p = 1)

splits(itr::SparseVectorSplitIterator) = (Split(itr.vec, itr.prev_pos), SparseVectorRunCleanup(vec))

struct SparseVectorSpikeLoop
    prev_pos
    vec
end

block_end(itr::SparseVectorSpikeLoop) = :($(itr.vec.pos)[$(itr.prev_pos)])

IteratorStyle(itr::SparseVectorSpikeLoop) = IterativeTruncateStyle()

struct SparseVectorRunCleanup
    vec
end

IteratorStyle(itr::SparseVectorRunCleanup) = TerminalStyle()


function lower(ex::Forall)
    idx = ex.idx
    lvls = get_tensors_with_idx(ex, idx)
    for tns in tensors(ex)
        replace(ex, tns=>)
    end
    iterators = map(get_iterator, tns)
    return quote
        $setup_iterators
        i = 0
        #The blocks here are two-part blocks, one for the spikes and one for the cleanup afterwards.
        $(unfold(i, iterators))
    end
end

function unfold(i, expression)
    style = unfold_style(expression)
    unfold(i, expression, style)
end

function unfold(i, blockstyle)
    block_ind = 0
    while $(!any(isempty(iterators)))
        i′ = $(min(map(get_block_end, )))
        $(
            process the block from i to i′ = min(block_ends)
            process_block(expression with blocks inserted)
        )
        if hascoord(itr1, coord) && hascoord(itr2, coord)
            do_filled
        elseif hascoord(itr1 && !itr2)
            do_filled
        elseif hascoord(itr1 && !itr2)
            do_filled
        end
        end
        if hascoord(itr2)
        end
    end
end

function unfold(i, expression, combinatorstyle)
    combinators = get_combinators(expression)
    for combo in product(combinators)
        switch = :(true)
        for (condition, block, iterator) in combo
            switch = :($switch && $condition)
            replace!(expression, iterator => block)
        end
        unfold(i, expression)
    end
    advance_blocks
end

function unfold(i, expression, loopcleanupstyle)
    combinators = get_splits(expression)
    while any 4
    while any 3
    while any 2
    while any 1
end

struct Spike
    default
    parent
end

lower_style(b::Spike) = SpikeStyle()

truncate(b::Spike, i′) = Combinator(:(i′ == block_end(b.parent)), Spike(b.default, b.parent), Run(b.default))

struct Run
    default
end

lower_style(b::Run) = SingleStyle()

truncate(b::Run, i′) = b

#okay, so the next step is coiteration

struct Call{F, Args}
    f::F
    args::Args
end

struct Forall{I, Ops}
    i::I
    ops::Ops
end

function lower(ex::Forall{I, Ops}, pos, iter)
    i = ex.i
    ex = map(ex) do tns
        if tns isa Level && tns.i == ex.i
            push!(iters, tns.itr)
            return tns.child
        end
    end
end