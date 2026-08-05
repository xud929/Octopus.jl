# U18 probe 4: does the method-overwrite guard's instrument work on this Julia?
root = ARGS[1]
prog = "Base.compilecache(Base.identify_package(\"OverwriteProbe\"))"
err = IOBuffer()
p = run(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$(root) -e $prog`,
                 stderr=err, stdout=devnull); wait=false)
wait(p)
text = String(take!(err))
println("exit success = ", success(p))
println("--- stderr ---"); println(text); println("--- end ---")
println("occursin 'Method overwriting is not permitted' : ",
        occursin("Method overwriting is not permitted", text))
println("occursin r\"Method definition .* overwritten\"  : ",
        occursin(r"Method definition .* overwritten", text))
