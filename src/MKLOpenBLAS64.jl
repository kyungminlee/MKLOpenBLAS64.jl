module MKLOpenBLAS64

export parse_mkl_headers
export get_symbol_list
export get_stem
export get_function_decl_list

using Clang

const LIBCLANG_INCLUDE = joinpath(dirname(Clang.LibClang.libclang), "..", "include", "clang-c") |> normpath
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
    if Sys.iswindows()
        if dynamic
            text = read(`"C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Community\\VC\\Tools\\MSVC\\14.28.29910\\bin\\HostX64\\x64\\dumpbin.exe" /exports "$(libpath)"`, String)
            lines = [strip(l) for l in split(text, "\n")]
            symbol_list = String[]
            for l in lines
                tokens = split(l)
                # @show l
                # @show tokens
                length(tokens) == 4 || continue
                try
                    parse(Int, tokens[1])
                    parse(Int, tokens[2]; base=16)
                    parse(Int, tokens[3]; base=16)
                    push!(symbol_list, tokens[4])
                catch
                end
            end
            return symbol_list
        else
            text = read(`"C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Community\\VC\\Tools\\MSVC\\14.28.29910\\bin\\HostX64\\x64\\dumpbin.exe" /exports /symbols "$(libpath)"`, String)
            lines = [strip(l) for l in split(text, "\n")]
            symbol_list = String[]
            for l in lines
                tokens = split(l)
                # @show l
                # @show tokens
                length(tokens) == 8 || continue
                try
                    parse(Int, tokens[1]; base=16)
                    parse(Int, tokens[2]; base=16)
                    tokens[3] == "SECT1" || continue
                    tokens[4] == "notype" || continue
                    tokens[5] == "()" || continue
                    tokens[6] == "External" || continue
                    tokens[7] == "|" || continue
                    push!(symbol_list, tokens[8])
                catch
                end
            end
            return symbol_list
        end
    else
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
end

function get_stem(openblas64_symbol::AbstractString)
    sym = lowercase(openblas64_symbol)
    # sym = openblas64_symbol
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
