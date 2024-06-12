using Pkg
#tempdir = mktempdir()
#Pkg.activate(tempdir)
#Pkg.develop(PackageSpec(path = joinpath(@__DIR__, "..")))
#Pkg.add(["BenchmarkTools", "PkgBenchmark", "MatrixDepot"])
#Pkg.resolve()

using Finch
using BenchmarkTools
using MatrixDepot
using SparseArrays
using FastClosures
using Polyester

include(joinpath(@__DIR__, "../docs/examples/bfs.jl"))
include(joinpath(@__DIR__, "../docs/examples/pagerank.jl"))
include(joinpath(@__DIR__, "../docs/examples/shortest_paths.jl"))
include(joinpath(@__DIR__, "../docs/examples/spgemm.jl"))
include(joinpath(@__DIR__, "../docs/examples/triangle_counting.jl"))

SUITE = BenchmarkGroup()

SUITE["high-level"] = BenchmarkGroup()

let
    k = Ref(0.0)
    A = Tensor(Dense(Sparse(Element(0.0))), fsprand(10000, 10000, 0.01))
    x = rand(1)
    y = rand(1)
    SUITE["high-level"]["permutedims(Dense(Sparse()))"] = @benchmarkable(permutedims($A, (2, 1)))
end

let
    k = Ref(0.0)
    A = Tensor(Dense(Dense(Element(0.0))), rand(10000, 10000))
    x = rand(1)
    y = rand(1)
    SUITE["high-level"]["permutedims(Dense(Dense()))"] = @benchmarkable(permutedims($A, (2, 1)))
end

let
    k = Ref(0.0)
    x = rand(1)
    y = rand(1)
    SUITE["high-level"]["einsum_spmv_compile_overhead"] = @benchmarkable(
        begin
            A, x, y = (A, $x, $y)
            @einsum y[i] += A[i, j] * x[j]
        end,
        setup = (A = Tensor(Dense(SparseList(Element($k[] += 1))), fsprand(1, 1, 1)))
    )
end

let
    A = Tensor(Dense(SparseList(Element(0.0))), fsprand(1, 1, 1))
    x = rand(1)
    SUITE["high-level"]["einsum_spmv_call_overhead"] = @benchmarkable(
        begin
            A, x = ($A, $x)
            @einsum y[i] += A[i, j] * x[j]
        end,
        seconds = 10.0 #Bug in benchmarktools, will be fixed soon.
    )
end

eval(let
    A = Tensor(Dense(SparseList(Element(0.0))), fsprand(1, 1, 1))
    x = rand(1)
    y = rand(1)
    @finch_kernel function spmv(y, A, x)
        for j=_, i=_
            y[i] += A[i, j] * x[j]
        end
    end
end)

let
    A = Tensor(Dense(SparseList(Element(0.0))), fsprand(1, 1, 1))
    x = rand(1)
    y = rand(1)
    SUITE["high-level"]["einsum_spmv_baremetal"] = @benchmarkable(
        begin
            A, x, y = ($A, $x, $y)
            spmv(y, A, x)
        end,
        evals = 1000
    )
end

SUITE["compile"] = BenchmarkGroup()

code = """
using Finch
A = Tensor(Dense(SparseList(Element(0.0))))
B = Tensor(Dense(SparseList(Element(0.0))))
C = Tensor(Dense(SparseList(Element(0.0))))

@finch (C .= 0; for i=_, j=_, k=_; C[j, i] += A[k, i] * B[k, i] end)
"""
cmd = pipeline(`$(Base.julia_cmd()) --project=$(Base.active_project()) --eval $code`, stdout = IOBuffer())

SUITE["compile"]["time_to_first_SpGeMM"] = @benchmarkable run(cmd)

let
    A = Tensor(Dense(SparseList(Element(0.0))))
    B = Tensor(Dense(SparseList(Element(0.0))))
    C = Tensor(Dense(SparseList(Element(0.0))))

    SUITE["compile"]["compile_SpGeMM"] = @benchmarkable begin
        A, B, C = ($A, $B, $C)
        Finch.execute_code(:ex, typeof(Finch.@finch_program_instance (C .= 0; for i=_, j=_, k=_; C[j, i] += A[k, i] * B[k, j] end; return C)))
    end
end

let
    A = Tensor(SparseList(SparseList(Element(0.0))))
    c = Scalar(0.0)

    SUITE["compile"]["compile_pretty_triangle"] = @benchmarkable begin
        A, c = ($A, $c)
        @finch_code (c .= 0; for i=_, j=_, k=_; c[] += A[i, j] * A[j, k] * A[i, k] end; return c)
    end
end

SUITE["graphs"] = BenchmarkGroup()

SUITE["graphs"]["pagerank"] = BenchmarkGroup()
for mtx in ["SNAP/soc-Epinions1", "SNAP/soc-LiveJournal1"]
    SUITE["graphs"]["pagerank"][mtx] = @benchmarkable pagerank($(pattern!(Tensor(SparseMatrixCSC(matrixdepot(mtx))))))
end

SUITE["graphs"]["bfs"] = BenchmarkGroup()
for mtx in ["SNAP/soc-Epinions1", "SNAP/soc-LiveJournal1"]
    SUITE["graphs"]["bfs"][mtx] = @benchmarkable bfs($(Tensor(SparseMatrixCSC(matrixdepot(mtx)))))
end

SUITE["graphs"]["bellmanford"] = BenchmarkGroup()
for mtx in ["Newman/netscience", "SNAP/roadNet-CA"]
    A = set_fill_value!(Tensor(SparseMatrixCSC(matrixdepot(mtx))), Inf)
    SUITE["graphs"]["bellmanford"][mtx] = @benchmarkable bellmanford($A)
end

SUITE["matrices"] = BenchmarkGroup()

SUITE["matrices"]["ATA_spgemm_inner"] = BenchmarkGroup()
for mtx in []#"SNAP/soc-Epinions1", "SNAP/soc-LiveJournal1"]
    A = Tensor(permutedims(SparseMatrixCSC(matrixdepot(mtx))))
    SUITE["matrices"]["ATA_spgemm_inner"][mtx] = @benchmarkable spgemm_inner($A, $A)
end

SUITE["matrices"]["ATA_spgemm_gustavson"] = BenchmarkGroup()
for mtx in ["SNAP/soc-Epinions1"]#], "SNAP/soc-LiveJournal1"]
    A = Tensor(SparseMatrixCSC(matrixdepot(mtx)))
    SUITE["matrices"]["ATA_spgemm_gustavson"][mtx] = @benchmarkable spgemm_gustavson($A, $A)
end

SUITE["matrices"]["ATA_spgemm_outer"] = BenchmarkGroup()
for mtx in ["SNAP/soc-Epinions1"]#, "SNAP/soc-LiveJournal1"]
    A = Tensor(SparseMatrixCSC(matrixdepot(mtx)))
    SUITE["matrices"]["ATA_spgemm_outer"][mtx] = @benchmarkable spgemm_outer($A, $A)
end

SUITE["indices"] = BenchmarkGroup()

function spmv32(A, x)
    y = Tensor(Dense{Int32}(Element{0.0, Float64, Int32}()))
    @finch (y .= 0; for i=_, j=_; y[i] += A[j, i] * x[j] end)
    return y
end

SUITE["indices"]["SpMV_32"] = BenchmarkGroup()
for mtx in ["SNAP/soc-Epinions1"]#, "SNAP/soc-LiveJournal1"]
    A = SparseMatrixCSC(matrixdepot(mtx))
    A = Tensor(Dense{Int32}(SparseList{Int32}(Element{0.0, Float64, Int32}())), A)
    x = Tensor(Dense{Int32}(Element{0.0, Float64, Int32}()), rand(size(A)[2]))
    SUITE["indices"]["SpMV_32"][mtx] = @benchmarkable spmv32($A, $x)
end

function spmv_p1(A, x)
    y = Tensor(Dense(Element(0.0)))
    @finch (y .= 0; for i=_, j=_; y[i] += A[j, i] * x[j] end)
    return y
end

SUITE["indices"]["SpMV_p1"] = BenchmarkGroup()
for mtx in ["SNAP/soc-Epinions1"]#, "SNAP/soc-LiveJournal1"]
    A = SparseMatrixCSC(matrixdepot(mtx))
    (m, n) = size(A)
    ptr = A.colptr .- 1
    idx = A.rowval .- 1
    A = Tensor(Dense(SparseList(Element(0.0, A.nzval), m, Finch.PlusOneVector(ptr), Finch.PlusOneVector(idx)), n))
    x = Tensor(Dense(Element(0.0)), rand(n))
    SUITE["indices"]["SpMV_p1"][mtx] = @benchmarkable spmv_p1($A, $x)
end

function spmv64(A, x)
    y = Tensor(Dense{Int64}(Element{0.0, Float64, Int64}()))
    @finch (y .= 0; for i=_, j=_; y[i] += A[j, i] * x[j] end)
    return y
end

SUITE["indices"]["SpMV_64"] = BenchmarkGroup()
for mtx in ["SNAP/soc-Epinions1"]#, "SNAP/soc-LiveJournal1"]
    A = SparseMatrixCSC(matrixdepot(mtx))
    A = Tensor(Dense{Int64}(SparseList{Int64}(Element{0.0, Float64, Int64}())), A)
    x = Tensor(Dense{Int64}(Element{0.0, Float64, Int64}()), rand(size(A)[2]))
    SUITE["indices"]["SpMV_64"][mtx] = @benchmarkable spmv64($A, $x)
end

SUITE["parallel"] = BenchmarkGroup()

function spmv_serial(A, x)
    y = Tensor(Dense{Int64}(Element{0.0, Float64}()))
    @finch begin
        y .= 0
        for i=_
            for j=_
                y[i] += A[j, i] * x[j]
            end
        end
        return y
    end
end

function spmv_threaded(A, x)
    y = Tensor(Dense{Int64}(Element{0.0, Float64}()))
    #=
    @finch begin
        y .= 0
        for i=parallel(_)
            for j=_
                y[i] += A[j, i] * x[j]
            end
        end
        return y
    end
    =#
    spmv_threaded_helper(y, A, x)
end

function spmv_threaded_helper(y::Tensor{DenseLevel{Int64, ElementLevel{0.0, Float64, Int64, Vector{Float64}}}}, A::Tensor{DenseLevel{Int64, SparseListLevel{Int64, Vector{Int64}, Vector{Int64}, ElementLevel{0.0, Float64, Int64, Vector{Float64}}}}}, x::Tensor{DenseLevel{Int64, ElementLevel{0.0, Float64, Int64, Vector{Float64}}}})
    @inbounds @fastmath(begin
        y_lvl = y.lvl
        y_lvl_2 = y_lvl.lvl
        y_lvl_val = y_lvl.lvl.val
        A_lvl = A.lvl
        A_lvl_2 = A_lvl.lvl
        A_lvl_ptr = A_lvl_2.ptr
        A_lvl_idx = A_lvl_2.idx
        A_lvl_2_val = A_lvl_2.lvl.val
        x_lvl = x.lvl
        x_lvl_val = x_lvl.lvl.val
        x_lvl.shape == A_lvl_2.shape || throw(DimensionMismatch("mismatched dimension limits ($(x_lvl.shape) != $(A_lvl_2.shape))"))
        Finch.resize_if_smaller!(y_lvl_val, A_lvl.shape)
        Finch.fill_range!(y_lvl_val, 0.0, 1, A_lvl.shape)
        val = y_lvl_val
        y_lvl_val = (Finch).moveto(y_lvl_val, CPU(Threads.nthreads()))
        x_lvl_val = (Finch).moveto(x_lvl_val, CPU(Threads.nthreads()))
        A_lvl_ptr = (Finch).moveto(A_lvl_ptr, CPU(Threads.nthreads()))
        A_lvl_idx = (Finch).moveto(A_lvl_idx, CPU(Threads.nthreads()))
        A_lvl_2_val = (Finch).moveto(A_lvl_2_val, CPU(Threads.nthreads()))
        f = @closure (i_4) -> @inbounds begin
            phase_start_2 = max(1, 1 + fld(A_lvl.shape * (i_4 + -1), Threads.nthreads()))
            phase_stop_2 = min(A_lvl.shape, fld(A_lvl.shape * i_4, Threads.nthreads()))
            if phase_stop_2 >= phase_start_2
                for i_7 = phase_start_2:phase_stop_2
                    y_lvl_q = (1 - 1) * A_lvl.shape + i_7
                    A_lvl_q = (1 - 1) * A_lvl.shape + i_7
                    A_lvl_2_q = A_lvl_ptr[A_lvl_q]
                    A_lvl_2_q_stop = A_lvl_ptr[A_lvl_q + 1]
                    if A_lvl_2_q < A_lvl_2_q_stop
                        A_lvl_2_i1 = A_lvl_idx[A_lvl_2_q_stop - 1]
                    else
                        A_lvl_2_i1 = 0
                    end
                    phase_stop_3 = min(x_lvl.shape, A_lvl_2_i1)
                    if phase_stop_3 >= 1
                        if A_lvl_idx[A_lvl_2_q] < 1
                            A_lvl_2_q = Finch.scansearch(A_lvl_idx, 1, A_lvl_2_q, A_lvl_2_q_stop - 1)
                        end
                        while true
                            A_lvl_2_i = A_lvl_idx[A_lvl_2_q]
                            if A_lvl_2_i < phase_stop_3
                                A_lvl_3_val = A_lvl_2_val[A_lvl_2_q]
                                x_lvl_q = (1 - 1) * x_lvl.shape + A_lvl_2_i
                                x_lvl_2_val = x_lvl_val[x_lvl_q]
                                y_lvl_val[y_lvl_q] += A_lvl_3_val * x_lvl_2_val
                                A_lvl_2_q += 1
                            else
                                phase_stop_5 = min(phase_stop_3, A_lvl_2_i)
                                if A_lvl_2_i == phase_stop_5
                                    A_lvl_3_val = A_lvl_2_val[A_lvl_2_q]
                                    x_lvl_q = (1 - 1) * x_lvl.shape + phase_stop_5
                                    x_lvl_2_val_2 = x_lvl_val[x_lvl_q]
                                    y_lvl_val[y_lvl_q] += A_lvl_3_val * x_lvl_2_val_2
                                    A_lvl_2_q += 1
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
        Threads.@threads for i_5 = 1:Threads.nthreads()
            f(i_5)
        end
        resize!(val, A_lvl.shape)
        (y = Tensor((DenseLevel){Int64}(y_lvl_2, A_lvl.shape)),)
    end)
end

SUITE["parallel"]["SpMV_serial"] = BenchmarkGroup()
SUITE["parallel"]["SpMV_threaded"] = BenchmarkGroup()
for (key, mtx) in [
    "SNAP/soc-Epinions1" => SparseMatrixCSC(matrixdepot("SNAP/soc-Epinions1")),
    "fsprand(10_000, 10_000, 0.01)" => fsprand(10_000, 10_000, 0.01)]
    A = Tensor(Dense{Int64}(SparseList{Int64}(Element{0.0, Float64, Int64}())), A)
    x = Tensor(Dense{Int64}(Element{0.0, Float64, Int64}()), rand(size(A)[2]))
    println(Threads.nthreads())
    SUITE["parallel"]["SpMV_serial"][key] = @benchmarkable spmv_serial($A, $x)
    SUITE["parallel"]["SpMV_threaded"][key] = @benchmarkable spmv_threaded($A, $x)
end

SUITE = SUITE["parallel"]
