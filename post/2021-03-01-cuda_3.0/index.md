+++
title = "CUDA.jl 3.0"
author = "Tim Besard"
hidden = true
+++

CUDA.jl 3.0 is a significant, semi-breaking release that features greatly improved
multi-tasking and multi-threading, support for CUDA 11.2 and its new memory allocator, and a
completely revamped cuDNN interface.

<!--more-->


## Improved multi-tasking and multi-threading

Traditionally, CUDA operations were enqueued on the global default stream, and many of these
operations (like copying memory, or synchronizing execution) were fully blocking. This posed
difficulties when using multiple tasks, each of which assumed to perform independent
operations (possibly on different devices, maybe even from a different CPU thread).
**CUDA.jl now uses a private stream for each Julia task, and avoids blocking operations
where possible, enabling task-based concurrent execution.**

A ~~picture~~ snippet of code is worth a thousand words, so let's have a look at some dummy
computation that both uses a library function (GEMM from CUBLAS) and a native Julia
broadcast kernel:

```julia
using CUDA, LinearAlgebra

function compute(a,b,c)
    mul!(c, a, b)
    broadcast!(sin, c, c)
    synchronize()
    c
end
```

To perform this computation concurrently, we can just use Julia's task-based programming
interfaces and wrap each computation in an `@async` block. To synchronize these tasks at the
end, we wrap in a `@sync` block. Finally, to visualize these computations in the profiler
trace below we use NVTX's `@range` macro:

```julia
function iteration(a,b,c)
    results = Vector{Any}(undef, 2)
    NVTX.@range "computation" @sync begin
        @async begin
            results[1] = compute(a,b,c)
        end
        @async begin
            results[2] = compute(a,b,c)
        end
    end
    NVTX.@range "comparison" Array(results[1]) == Array(results[2])
end
```

We then invoke this function using some random data:

```julia
function main(N=1024)
    a = CUDA.rand(N,N)
    b = CUDA.rand(N,N)
    c = CUDA.rand(N,N)

    # make sure this data can be used by other tasks!
    synchronize()

    # warm-up
    iteration(a,b,c)
    GC.gc(true)

    NVTX.@range "main" iteration(a,b,c)
end
```

The snippet above illustrates one breaking aspect of this change: Because each task uses its
own stream, **you now need to synchronize when re-using data in another task.** Although it
is unlikely that any user code was relying on the old behavior, it is technically a breaking
change.

If we profile these computations, we can see how the execution was overlapped:

<!-- {{< img "task_based_concurrency.png" "Overlapping execution on the GPU using task-based concurrency" >}} -->

The region highlighted in green was spent enqueueing operations, which includes the call to
`synchronize()`. This used to be a globally-synchronizing operation, whereas now it only
synchronizes the task-local stream while yielding to the Julia scheduler so that it can
continue executing other tasks. **For synchronizing the entire device, use the new
`synchronize_all()` function.**

The remainder of computation was then spent executing kernels. Here, these executions were
overlapping, but that obviously depends on the exact characteristics of the computations and
your GPU. The same approach however can be used for multi-GPU programming, where each task
targets a different device. It is also possible to use different threads for each task.

Note that not all operations have been made fully asynchronous yet. For example, copying
memory to or from the GPU will currently still synchronize execution, and thus inhibit
switching to another task. That is why the example above only called `synchronize()` in the
compute task, and copied the memory to the host in the parent task.


## CUDA 11.2 and stream-ordered allocations

CUDA.jl now also fully supports CUDA 11.2, and it will default to using that version of the
toolkit if your driver supports it. The release came with several new features, such as [the
new stream-ordered memory
allocator](https://developer.nvidia.com/blog/enhancing-memory-allocation-with-new-cuda-11-2-features/).
Without going into details, it is now possible to asynchonously allocate memory, obviating
much of the need to cache those allocations in a memory pool. Initial benchmarks have shown
nice speed-ups from using this allocator, while lowering memory pressure and thus reducing
invocations of the Julia garbage collector.

When using CUDA 11.2, CUDA.jl will default to the CUDA-backed memory pool, and disable its
own caching layer. If you want to compare performance, you can still use the old allocator
and caching memory pool by setting the `JULIA_CUDA_MEMORY_POOL` environment variable to,
e.g. `binned`. On older versions of CUDA, the `binned` pool is still used by default.


## Revamped cuDNN interface

As part of this release, the cuDNN wrappers have been completely revamped by
[@denizyuret](https://github.com/denizyuret). The goal of the redesign is to more faithfully
map the cuDNN API to more natural Julia functions, so that packages like Knet.jl or NNlib.jl
can more easily use advanced cuDNN features without having to resort to low-level C calls.
For more details, refer to [the design
document](https://github.com/JuliaGPU/CUDA.jl/blob/da7c6eee82d6ea0eee1cb75c8589c8a92b0bc474/lib/cudnn/README.md).
