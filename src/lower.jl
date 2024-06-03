@kwdef mutable struct LowerJulia <: AbstractCompiler
    code = JuliaContext()
    needs_return = freshen(code, :needs_return)
    result = freshen(code, :result)
    algebra = DefaultAlgebra()
    mode = :fast
    symbolic = SymbolicContext(algebra = algebra)
    scope = ScopeContext()
end

get_binding(ctx::LowerJulia, var) = get_binding(ctx.scope, var)
has_binding(ctx::LowerJulia, var) = has_binding(ctx.scope, var)
set_binding!(ctx::LowerJulia, var, val) = set_binding!(ctx.scope, var, val)
set_declared!(ctx::LowerJulia, var, val) = set_declared!(ctx.scope, var, val)
set_frozen!(ctx::LowerJulia, var, val) = set_frozen!(ctx.scope, var, val)
set_thawed!(ctx::LowerJulia, var, val) = set_thawed!(ctx.scope, var, val)
get_mode(ctx::LowerJulia, var) = get_mode(ctx.scope, var)
function open_scope(f::F, ctx::LowerJulia) where {F}
    open_scope(ctx.scope) do scope_2
        f(LowerJulia(ctx.code, ctx.needs_return, ctx.result, ctx.algebra, ctx.mode, ctx.symbolic, scope_2))
    end
end

push_preamble!(ctx::LowerJulia, thunk) = push_preamble!(ctx.code, thunk)
push_epilogue!(ctx::LowerJulia, thunk) = push_epilogue!(ctx.code, thunk)
get_task(ctx::LowerJulia) = get_task(ctx.code)
freshen(ctx::LowerJulia, tags...) = freshen(ctx.code, tags...)

get_algebra(ctx::LowerJulia) = ctx.algebra
get_static_hash(ctx::LowerJulia) = get_static_hash(ctx.symbolic)
prove(ctx::LowerJulia, root) = prove(ctx.symbolic, root)
simplify(ctx::LowerJulia, root) = simplify(ctx.symbolic, root)

function contain(f, ctx::LowerJulia; kwargs...)
    contain(ctx.code; kwargs...) do code_2
        f(LowerJulia(code_2, ctx.needs_return, ctx.result, ctx.algebra, ctx.mode, ctx.symbolic, ctx.scope))
    end
end

(ctx::AbstractCompiler)(root) = ctx(root, Stylize(ctx, root)(root))
(ctx::AbstractCompiler)(root, style) = lower(ctx, root, style)
#(ctx::AbstractCompiler)(root, style) = (println(); println(); display(root); display(style); lower(ctx, root, style))
function cache!(ctx::AbstractCompiler, var, val)
    val = finch_leaf(val)
    isconstant(val) && return val
    var = freshen(ctx,var)
    val = simplify(ctx, val)
    push_preamble!(ctx, quote
        $var = $(contain(ctx_2 -> ctx_2(val), ctx))
    end)
    return cached(value(var, Any), literal(val))
end

resolve(ctx, node) = node
function resolve(ctx::AbstractCompiler, node::FinchNode)
    if node.kind === virtual
        return node.val
    elseif node.kind === variable
        return resolve(ctx, get_binding(ctx, node))
    elseif node.kind === index
        return resolve(ctx, get_binding(ctx, node))
    else
        error("unimplemented $node")
    end
end

(ctx::AbstractCompiler)(root::Union{Symbol, Expr}, ::DefaultStyle) = root

@kwdef struct Stylize{Ctx}
    ctx::Ctx
    root
end

function (ctx::Stylize)(node)
    if istree(node)
        return mapreduce(ctx, result_style, arguments(node); init=DefaultStyle())
    end
    return DefaultStyle()
end

function (ctx::Stylize)(node::FinchNode)
    if node.kind === virtual
        return ctx(node.val)
    elseif node.kind === access
        return mapreduce(ctx, result_style, arguments(node); init=stylize_access(ctx, node, node.tns))
    elseif istree(node)
        return mapreduce(ctx, result_style, arguments(node); init=DefaultStyle())
    else
        return DefaultStyle()
    end
end

stylize_access(ctx, node, @nospecialize tns) = DefaultStyle()
stylize_access(ctx, node, tns::FinchNode) = stylize_access(ctx, node, resolve(ctx, tns))

function lower(ctx::AbstractCompiler, root, ::DefaultStyle)
    node = finch_leaf(root)
    if node.kind === virtual
        error("don't know how to lower $root")
    end
    ctx(node)
end

function lower(ctx::AbstractCompiler, root::FinchNode, ::DefaultStyle)
    if root.kind === value
        return root.val
    elseif root.kind === index
        return ctx(get_binding(ctx, root)) #This unwraps indices that are virtuals. Arguably these virtuals should be precomputed, but whatevs.
    elseif root.kind === literal
        if typeof(root.val) === Symbol ||
          typeof(root.val) === Expr ||
          typeof(root.val) === Missing
            return QuoteNode(root.val)
        else
            return root.val
        end
    elseif root.kind === block
        if isempty(root.bodies)
            return quote end
        else
            head = root.bodies[1]
            body = block(root.bodies[2:end]...)
            preamble = quote end

            #The idea here is that we expect parent blocks to eagerly process
            #child blocks, so the effects of the statements like freeze or thaw
            #should always be visible to any subsequent statement, even if its
            #in a different block.
            if head.kind === block
                ctx(block(head.bodies..., body))
            elseif head.kind === declare
                val_2 = declare!(ctx, get_binding(ctx, head.tns), head.init)
                set_declared!(ctx, head.tns, val_2)
            elseif head.kind === freeze
                val_2 = freeze!(ctx, get_binding(ctx, head.tns))
                set_frozen!(ctx, head.tns, val_2)
            elseif head.kind === thaw
                val_2 = thaw!(ctx, get_binding(ctx, head.tns))
                set_thawed!(ctx, head.tns, val_2)
            else
                preamble = contain(ctx) do ctx_2
                    ctx_2(instantiate!(ctx_2, head))
                end
            end

            quote
                $preamble
                $(contain(ctx) do ctx_2
                    (ctx_2)(body)
                end)
            end
        end
    elseif root.kind === define
        @assert root.lhs.kind === variable
        set_binding!(ctx, root.lhs, cache!(ctx, root.lhs.name, root.rhs))
        contain(ctx) do ctx_2
            open_scope(ctx_2) do ctx_3
                ctx_3(root.body)
            end
        end
    elseif (root.kind === declare || root.kind === freeze || root.kind === thaw)
        #these statements only apply to subsequent statements in a block
        #if we try to lower them directly they are a no-op
        #arguably, the declare, freeze, or thaw nodes should never reach this case but we'll leave that alone for now
        quote end
    elseif root.kind === access
        return lower_access(ctx, root, resolve(ctx, root.tns))
    elseif root.kind === call
        root = simplify(ctx, root)
        if root.kind === call 
            if root.op == literal(and)
                if isempty(root.args)
                    return true
                else
                    reduce((x, y) -> :($x && $y), map(ctx, root.args)) #TODO This could be better. should be able to handle empty case
                end
            elseif root.op == literal(or)
                if isempty(root.args)
                    return false
                else
                    reduce((x, y) -> :($x || $y), map(ctx, root.args))
                end
            else
                :($(ctx(root.op))($(map(ctx, root.args)...)))
            end
         else 
           return ctx(root) 
         end
    elseif root.kind === cached
        return ctx(root.arg)
    elseif root.kind === loop
        @assert root.idx.kind === index
        @assert root.ext.kind === virtual
        lower_loop(ctx, root, root.ext.val)
    elseif root.kind === sieve
        cond = freshen(ctx,:cond)
        push_preamble!(ctx, :($cond = $(ctx(root.cond))))
    
        return quote
            if $cond
                $(contain(ctx) do ctx_2
                    open_scope(ctx_2) do ctx_3
                        ctx_3(root.body)
                    end
                end)
            end
        end
    elseif root.kind === virtual
        ctx(root.val)
    elseif root.kind === assign
        if root.lhs.kind === access
            @assert root.lhs.mode.val === updater
            rhs = ctx(simplify(ctx, call(root.op, root.lhs, root.rhs)))
        else
            rhs = ctx(root.rhs)
        end
        lhs = ctx(root.lhs)
        return :($lhs = $rhs)
    elseif root.kind === variable
        return ctx(get_binding(ctx, root))
    elseif root.kind === yieldbind
        contain(ctx) do ctx_2
            quote
                if $(ctx.needs_return)
                    $(ctx.result) = (; $(map(root.args) do tns
                        name = getroot(tns).name
                        Expr(:kw, name, ctx_2(tns))
                    end...), )
                    $(ctx.needs_return) = false
                end
            end
        end
    else
        error("unimplemented ($root)")
    end
end

function lower_access(ctx, node, tns)
    tns = ctx(tns)
    idxs = map(ctx, node.idxs)
    :($(ctx(tns))[$(idxs...)])
end

function lower_access(ctx, node, tns::Number)
    @assert node.mode.val === reader
    tns
end

function lower_loop(ctx, root, ext)
    root_2 = Rewrite(Postwalk(@rule access(~tns, ~mode, ~idxs...) => begin
        if !isempty(idxs) && root.idx == idxs[end]
            protos = [(mode.val === reader ? defaultread : defaultupdate) for _ in idxs]
            tns_2 = unfurl(ctx, tns, root.ext.val, mode.val, protos...)
            access(tns_2, mode, idxs...)
        end
    end))(root)
    return ctx(root_2, result_style(LookupStyle(), Stylize(ctx, root_2)(root_2)))
end

lower_loop(ctx, root, ext::ParallelDimension) = 
    lower_parallel_loop(ctx, root, ext, ext.device)
function lower_parallel_loop(ctx, root, ext::ParallelDimension, device::VirtualCPU)
    root = ensure_concurrent(root, ctx)
    
    tid = index(freshen(ctx, :tid))
    i = freshen(ctx, :i)

    decl_in_scope = unique(filter(!isnothing, map(node-> begin
        if @capture(node, declare(~tns, ~init))
            tns 
        end
    end, PostOrderDFS(root.body))))

    used_in_scope = unique(filter(!isnothing, map(node-> begin
        if @capture(node, access(~tns, ~mode, ~idxs...))
            getroot(tns)
        end
    end, PostOrderDFS(root.body))))

    root_2 = loop(tid, Extent(value(i, Int), value(i, Int)),
        loop(root.idx, ext.ext,
            sieve(access(VirtualSplitMask(device.n), reader, root.idx, tid),
                root.body
            )
        )
    )

    for tns in setdiff(used_in_scope, decl_in_scope)
        virtual_moveto(ctx, resolve(ctx, tns), device)
    end

    return quote
        Threads.@threads for $i = 1:$(ctx(device.n))
            $(contain(ctx) do ctx_2
                subtask = VirtualCPUThread(value(i, Int), device, ctx_2.code.task)
                contain(ctx_2, task=subtask) do ctx_3
                    for tns in intersect(used_in_scope, decl_in_scope)
                        virtual_moveto(ctx_3, resolve(ctx_3, tns), subtask)
                    end
                    contain(ctx_3) do ctx_4
                        open_scope(ctx_4) do ctx_5
                            ctx_5(instantiate!(ctx_5, root_2))
                        end
                    end
                end
            end)
        end
    end
end
