using MKLOpenBLAS64
using TOML
using Clang
using CMakeWrapper
using Libdl

srcdir = "src"
builddir = "./build"

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

function get_openblas64_path()
    for x in dllist()
        if occursin("openblas64_", x)
            return x
        end
    end
    return nothing
end


function main()
    config = TOML.parsefile("config.toml")
    mkl_headers = config["mkl_headers"]
    mkl_libraries = config["mkl_libraries"]

    if !ispath(builddir)
        mkpath(builddir; force=true)
    end
    cp(joinpath(srcdir, "mklopenblas64.h"), joinpath(builddir, "mklopenblas64.h"); force=true)
    cp(joinpath(srcdir, "mklopenblas64-util.c"), joinpath(builddir, "mklopenblas64-util.c"); force=true)
    cp(joinpath(srcdir, "CMakeLists.txt"), joinpath(builddir, "CMakeLists.txt"); force=true)

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

    openblas64_path = get_openblas64_path()
    isnothing(openblas64_path) && error("Julia's openblas library not found")
    openblas64_exports = get_symbol_list(openblas64_path)
    ilp64_exports = vcat([get_symbol_list(lib; dynamic=false) for lib in mkl_libraries]...)

    missing_caller_list = String[]
    open(joinpath(builddir, "mklopenblas64.c", "w") do outfp
        println(outfp, "#include \"mklopenblas64.h\"")

        for caller in openblas64_exports
            endswith(caller, "64_") || continue # only wrap functions that end with 64_. No internal functions
            in(caller, util_list) && continue

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

    open(joinpath(builddir, "options.cmake"), "w") do outfp
        write(outfp, """
        set(MKL_INCLUDE_PATH "/usr/include/mkl")
        set(MKL_LIBRARIES
            "-Wl,--start-group"
        """)
        for mkl_lib in mkl_libraries
            write(outfp, "$mkl_lib\n")
        end
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
        open(joinpath(builddir, "missing.log"), "w") do outfp
            for m in missing_caller_list
                println(outfp, m)
            end
        end
    end
    run(Cmd([CMakeWrapper.cmake_executable, builddir, "-B", builddir, "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_INSTALL_PREFIX=stage"]))
    run(Cmd([CMakeWrapper.cmake_executable, "--build", builddir, "--target", "install", "--config", "Release"]))
end

main()
