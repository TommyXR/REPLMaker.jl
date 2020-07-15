module REPLMaker

export generate_custom_repl, add_repl!

using REPL
import REPL: REPL, LineEdit, REPLCompletions



mutable struct CusREPLCompletionProvider{T} <: LineEdit.CompletionProvider
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


    custom_mode.on_enter = jl_repl.on_enter
    custom_mode.on_done = jl_repl.on_done


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
