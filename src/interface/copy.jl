@staged function copyto_helper!(dst, src)
    ndims(dst) > ndims(src) && throw(DimensionMismatch("more dimensions in destination than source"))
    ndims(dst) < ndims(src) && throw(DimensionMismatch("less dimensions in destination than source"))
    idxs = [Symbol(:i_, n) for n = 1:ndims(dst)]
    exts = Expr(:block, (:($idx = _) for idx in reverse(idxs))...)
    return quote
        @finch mode=:fast begin
            dst .= $(fill_value(dst))
            $(Expr(:for, exts, quote
                dst[$(idxs...)] = src[$(idxs...)]
            end))
        end
        return dst
    end
end

Base.copyto!(dst::AbstractTensor, src::AbstractTensor) =
    copyto_helper!(dst, src)

Base.copyto!(dst::AbstractTensor, src::AbstractArray) =
    copyto_helper!(dst, src)

Base.copyto!(dst::AbstractArray, src::AbstractTensor) =
    copyto_helper!(dst, src)

function copyto_swizzled!(dst, src, perm)
    if issorted(perm)
        return copyto_helper!(dst, src)
    else
        tmp = rep_construct(permutedims_rep(data_rep(src), perm))
        tmp = copyto_helper!(swizzle(tmp, invperm(perm)...), src)
        return copyto_helper!(dst, tmp.body)
    end
end

Base.copyto!(dst::AbstractArray, src::SwizzleArray{dims}) where {dims} =
    copyto_swizzled!(dst, src.body, dims)

Base.copyto!(dst::AbstractTensor, src::SwizzleArray{dims}) where {dims} =
    copyto_swizzled!(dst, src.body, dims)

Base.copyto!(dst::SwizzleArray{dims}, src::SwizzleArray{dims2}) where {dims, dims2} =
    swizzle(copyto!(dst.body, swizzle(src, invperm(dims)...)), dims...)

Base.copyto!(dst::SwizzleArray{dims}, src::AbstractTensor) where {dims} =
    swizzle(copyto!(dst.body, swizzle(src, invperm(dims)...)), dims...)

Base.copyto!(dst::SwizzleArray{dims}, src::AbstractArray) where {dims} =
    swizzle(copyto!(dst.body, swizzle(src, invperm(dims)...)), dims...)

function Base.permutedims(src::AbstractTensor)
    @assert ndims(src) == 2
    permutedims(src, (2, 1))
end

function Base.permutedims(src::AbstractTensor, perm)
    dst = similar(src)
    copyto!(dst, swizzle(src, perm...))
end

"""
    dropfills(src)

Drop the fill values from `src` and return a new tensor with the same shape and
format.
"""
dropfills(src) = dropfills!(similar(src), src)

"""
    dropfills!(dst, src)

Copy only the non- fill values from `src` into `dst`. The shape and format of
`dst` must match `src`
"""
dropfills!(dst::AbstractTensor, src) = dropfills_helper!(dst, src)
dropfills!(dst::SwizzleArray{dims}, src::SwizzleArray{dims}) where {dims} = swizzle(dropfills_helper!(dst.body, src.body), dims...)

@staged function dropfills_helper!(dst, src)
    ndims(dst) > ndims(src) && throw(DimensionMismatch("more dimensions in destination than source"))
    ndims(dst) < ndims(src) && throw(DimensionMismatch("less dimensions in destination than source"))
    idxs = [Symbol(:i_, n) for n = 1:ndims(dst)]
    exts = Expr(:block, (:($idx = _) for idx in reverse(idxs))...)
    T = eltype(dst)
    d = fill_value(dst)
    return quote
        @finch begin
            dst .= $(fill_value(dst))
            $(Expr(:for, exts, quote
                let tmp = src[$(idxs...)]
                    if !isequal(tmp, $d)
                        dst[$(idxs...)] = tmp
                    end
                end
            end))
        end
        return dst
    end
end