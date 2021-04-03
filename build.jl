using MKLOpenBLAS64
using TOML
using Clang
using CMake

srcdir = "src"

util_list = [
    "openblas_get_config64_",
    "openblas_get_corename64_",
    "openblas_get_num_procs64_",
    "openblas_get_num_procs_64_",
    "openblas_get_num_threads64_",
    "openblas_get_num_threads_64_",
    "openblas_get_parallel64_",
    "openblas_get_parallel_64_",
    "openblas_set_num_threads64_",
    "openblas_set_num_threads_64_",
    "goto_set_num_threads64_",
    "lapack_make_complex_double64_",
    "lapack_make_complex_float64_",
]

function main()
    config = TOML.parsefile("config.toml")
    mkl_headers = config["mkl_headers"]
    mkl_libraries = config["mkl_libraries"]
    julia_root = config["julia_root"]

    trans_units = parse_mkl_headers(mkl_headers)

    callee_decl_list = Dict()
    for trans_unit in trans_units, decl in get_function_decl_list( getcursor(trans_unit) )
        stem = get_stem(decl.name)
        if haskey(callee_decl_list, stem)
            push!(callee_decl_list[stem], decl)
        else
            callee_decl_list[stem] = [decl]
        end
    end

    openblas64_exports = get_symbol_list("$julia_root/lib/julia/libopenblas64_.so")
    ilp64_exports = vcat([get_symbol_list(lib; dynamic=false) for lib in mkl_libraries]...)

    missing_caller_list = String[]
    open("$(srcdir)/mklopenblas64.c", "w") do outfp
        println(outfp, "#include \"mklopenblas64.h\"")

        for caller in openblas64_exports
            endswith(caller, "64_") || continue # only wrap functions that end with 64_. No internal functions

            caller_stem = get_stem(caller)
            if !haskey(callee_decl_list, caller_stem)
                push!(missing_caller_list, caller)
                continue
            end

            select_callee_decl = nothing
            for callee_decl in callee_decl_list[caller_stem]
                if callee_decl.name ∈ ilp64_exports
                    select_callee_decl = callee_decl
                    break
                end
            end

            if isnothing(select_callee_decl)
                @warn "stem $caller_stem not found in ilp64_exports"
                continue
            end
            callee_decl = select_callee_decl

            ret = callee_decl.return_type == "void" ? "" : "return "
            fparams = join(["$t $a" for (t, a) in zip(callee_decl.param_types, callee_decl.param_names)], ", ")
            fargs = join(["$a" for a in callee_decl.param_names], ", ")

            println(outfp, """
            API_EXPORT
            $(callee_decl.return_type)
            $(caller)($fparams)
            {
                $(ret)$(callee_decl.name)($fargs);
            }
            """)
        end
    end

    open("options.cmake", "w") do outfp
        write(outfp, """
        set(MKL_INCLUDE_PATH "/usr/include/mkl")
        set(MKL_LIBRARIES
            "-Wl,--start-group"
        """)
        for mkl_lib in mkl_libraries
            write(outfp, "$mkl_lib\n")
        end
            # /usr/lib/x86_64-linux-gnu/libmkl_gf_ilp64.a
            # /usr/lib/x86_64-linux-gnu/libmkl_gnu_thread.a
            # /usr/lib/x86_64-linux-gnu/libmkl_core.a
            # /usr/lib/x86_64-linux-gnu/liblapacke64.a
        write(outfp, """
            "-Wl,--end-group"
            -lgomp -lpthread -lm -ldl
        )
        """)
    end

    # missing_caller_list = [x for x in missing_caller_list if x ∉ util_list]
    if !isempty(missing_caller_list)
        @info "Missing symbols:"
        for m in missing_caller_list
            @info m
        end
    end

    run(Cmd([CMake.cmake, "-B", "build", "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_INSTALL_PREFIX=stage"]))
    run(Cmd([CMake.cmake, "--build", "build", "--target", "install", "--config", "Debug"]))

end


main()
