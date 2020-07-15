module REPLMaker

export generate_custom_repl, add_repl_mode!, add_repl_mode, register!

using REPL
import REPL: REPL, LineEdit, REPLCompletions


mutable struct CusREPLCompletionProvider <: LineEdit.CompletionProvider
    glossary::Dict{String, Function}
end

CusREPLCompletionProvider() = CusREPLCompletionProvider(Dict())


function parse_status(glossary, script::String)

    tokens = split(script, r"\s+")

    command = try
        glossary[tokens[1]]
    catch e
        e isa KeyError && return :error
        throw(e)
    end

        
    return :ok
end

function repl_eval(script::String, stdout::IO, stderr::IO, glossary)
    tokens = split(script, r"\s+")

    try
        command = glossary[tokens[1]]
        command(tokens[2:end]...)

    
    catch e
        if e isa KeyError
            println(stderr, "Command not recognized")
        else
            showerror(stderr, e)
        end

    end

end


function LineEdit.complete_line(c::CusREPLCompletionProvider, s)
    buf = s.input_buffer
    partial = String(buf.data[1:buf.ptr-1])

    full = LineEdit.input_string(s)

    ret, range, should_complete = REPLCompletions.bslash_completions(full, lastindex(partial))[2]

    if length(ret) > 0 && should_complete
        return map(REPLCompletions.completion_text, ret), partial[range], should_complete
    end
    
    tokens = split(partial, r"\s+")
    tocomplete = tokens[1]

    matches = filter(keys(c.glossary)) do v
        startswith(v, tocomplete)
    end


    if length(matches) > 0
        return matches |> collect, "sting", false
    end

    

    return String[], 0:-1, false
end


function register!(repl::LineEdit.Prompt, commands::Dict{String, T} where T <: Function)
    if !isa(repl.complete, CusREPLCompletionProvider)
        throw(TypeError(:register!, "repl", CusREPLCompletionProvider, typeof(repl.complete)))
    end

    merge!(repl.complete.glossary, commands)
    
    return nothing
end

function register!(repl::LineEdit.Prompt, p::Pair{String, T} where T <: Function)
    register!(repl, Dict(p))
end







function generate_custom_repl(prompt; prompt_prefix="", prompt_suffix="", sticky=true, share_history=true, autocomplete=true)

    custom_mode = LineEdit.Prompt(prompt; prompt_prefix=prompt_prefix, prompt_suffix=prompt_suffix, sticky=sticky)


    completion = CusREPLCompletionProvider()
    jl_repl = Base.active_repl.interface.modes[1]


    if share_history
        hist = jl_repl.hist
        hist.mode_mapping[Symbol(prompt)] = custom_mode

        custom_mode.hist = hist

        
    else

        hist = REPL.REPLHistoryProvider(Dict{Symbol,Any}(Symbol(prompt) => custom_mode))

        REPL.history_reset_state(hist)

        custom_mode.hist = hist
    end



    if autocomplete
        custom_mode.complete = completion
    end


    custom_mode.on_enter = s -> begin
        status = parse_status(completion.glossary, String(take!(copy(LineEdit.buffer(s)))))

        status == :ok || status == :error
    end


    custom_mode.on_done = (s, buffer, ok) -> begin
        if !ok
            return REPL.transition(s, :abort)
        end

       script = String(take!(buffer)) 

       if !isempty(strip(script))
            REPL.reset(Base.active_repl)

            try
                repl_eval(
                    script,
                    Base.active_repl.t.out_stream,
                    Base.active_repl.t.err_stream,
                    completion.glossary)

            catch y
                Base.with_output_color(:red, stderr) do io
                    print(io, "ERROR: ")
                    showerror(io, y)
                    println(stderr)
                end
            end

       end
       REPL.prepare_next(Base.active_repl)
       REPL.reset_state(s)
       s.current_mode.sticky || REPL.transition(s, jl_repl)
    end


    search_prompt, skeymap = LineEdit.setup_search_keymap(hist)
    prefix_prompt, pkeymap = LineEdit.setup_prefix_keymap(hist, custom_mode)

    
    default_keymap = REPL.mode_keymap(jl_repl)
    
    # Ctrl + C doesn't exit custom repl if sticky
    if sticky
        delete!(default_keymap, "^C")
    end

    keymap = Dict{Any,Any}[
        skeymap, default_keymap, pkeymap, LineEdit.history_keymap,
        LineEdit.default_keymap, LineEdit.escape_defaults]

    custom_mode.keymap_dict = LineEdit.keymap(keymap)


    return custom_mode
end


function add_repl_mode!(repl, custom_repl, symbol)
    mirepl = isdefined(repl, :mi) ? repl.mi : repl
    main_mode = mirepl.interface.modes[1]

    push!(mirepl.interface.modes, custom_repl)

    custom_prompt_keymap = Dict{Any, Any}(
        symbol => function (s, args...)
            if isempty(s) || position(LineEdit.buffer(s)) == 0
                buf = copy(LineEdit.buffer(s))
                LineEdit.transition(s, custom_repl) do
                    LineEdit.state(s, custom_repl).input_buffer = buf
                end
            else
                LineEdit.edit_insert(s, symbol)
            end
        end)

    main_mode.keymap_dict = LineEdit.keymap_merge(main_mode.keymap_dict, custom_prompt_keymap)

    return nothing
end


add_repl_mode(custom_repl, symbol) = add_repl_mode!(Base.active_repl, custom_repl, symbol)





end # module
