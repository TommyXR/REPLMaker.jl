# REPLMaker.jl

This is a tool to make custom REPL modes in Julia.

First, generate a new REPL Prompt:
```julia
c = generate_custom_repl("custom> ") # Many kwargs available, see source
```

You can then register statements and associate them with functions
```julia
register!(c, "print"=>println)
```

Finally, add the Prompt to the REPL list, choose a prefix and you're good to go.
```julia
add_repl_mode(c, raw"$")

julia> $
custom> print someword
someword
```

