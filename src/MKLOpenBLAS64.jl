module MKLOpenBLAS64

export parse_mkl_headers
export get_symbol_list
export get_stem
export get_function_decl_list

using Clang
using Clang.LibClang.Clang_jll

const LIBCLANG_INCLUDE = joinpath(dirname(Clang_jll.libclang_path), "..", "include", "clang-c") |> normpath
const LIBCLANG_HEADERS = [joinpath(LIBCLANG_INCLUDE, header) for header in readdir(LIBCLANG_INCLUDE) if endswith(header, ".h")]

function parse_mkl_headers(mkl_headers)
    trans_units = parse_headers(
        mkl_headers,
        args=["-DMKL_ILP64=1", "-Dlapack_int=long long", "-DOPENBLAS_USE64BITINT=1"],
        includes=vcat(LIBCLANG_INCLUDE, CLANG_INCLUDE)
    )
    return trans_units
end

function get_symbol_list(libpath::AbstractString; dynamic::Bool=false)
    if dynamic
        text = read(`nm -D "$(libpath)"`, String)
    else
        text = read(`nm "$(libpath)"`, String)
    end
    lines = [l for l in split(text, "\n") if length(l) >= 18 && l[18] == 'T']
    symbol_table = [tuple(split(l, " ")...) for l in lines]
    return [symbol_name
        for (symbol_address, symbol_type, symbol_name) in symbol_table
            if symbol_type == "T" || symbol_type == "t"
    ]
end

function get_stem(openblas64_symbol::AbstractString)
    # sym = lowercase(openblas64_symbol)
    sym = openblas64_symbol
    if endswith(sym, "_64_")
        sym = sym[1:end-4]
    elseif endswith(sym, "64_")
        sym = sym[1:end-3]
    elseif endswith(sym, "_")
        sym = sym[1:end-1]
    end
    # if startswith(sym, "mkl_")
    #     sym = sym[5:end]
    # end
    return sym
end

function get_function_decl_list(root_cursor)
    header = spelling(root_cursor)

    @info "parsing header $header"
    out = []
    for (i, child) in enumerate(children(root_cursor))
        filename(child) != header && continue  # skip if cursor filename is not in the headers to be wrapped
        kind(child) != Clang.CXCursor_FunctionDecl && continue # only function declaration

        child_spelling = spelling(child)
        isempty(child_spelling) && continue

        ftype = spelling(return_type(child))
        fname = child_spelling

        fparam_types = [spelling(argtype(type(child), i)) for i in 0:(argnum(child)-1)]
        fparam_names = [spelling(argument(child, i)) for i in 0:(argnum(child)-1)]
        for (iparam, name) in enumerate(fparam_names)
            if isempty(name)
                fparam_names[iparam] = "arg$(iparam)"
            end
        end
        stem = get_stem(fname)
        push!(out, (name=fname, return_type=ftype, param_types=fparam_types, param_names=fparam_names))
    end # for child
    return out
end

end # module MKLOpenBLAS64