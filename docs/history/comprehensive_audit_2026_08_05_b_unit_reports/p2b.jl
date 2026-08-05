using Octopus
expr_has_box(x) = x isa GlobalRef ? (x.mod === Core && x.name === :Box) :
                  x isa Expr ? any(expr_has_box, x.args) : false

code = """
function _u18_box_plain(n)
    x = 0
    f = () -> (x += 1)
    for i in 1:n
        f()
    end
    return x
end
"""
Base.include_string(Octopus, code, "pic_cpu.jl")
println(":_u18_box_plain in names? ",
        :_u18_box_plain in names(Octopus; all=true, imported=false))
for m in methods(Octopus._u18_box_plain)
    ci = Base.uncompressed_ir(m)
    println("  ", m, "  module=", m.module, "  file=", basename(String(m.file)),
            "  hasbox=", any(expr_has_box, ci.code))
end
# also the closure body methods
for nm in names(Octopus; all=true, imported=false)
    s = String(nm)
    occursin("_u18_box_plain", s) || continue
    f = getfield(Octopus, nm)
    f isa Union{Function,Type} || continue
    for m in methods(f)
        ci = try Base.uncompressed_ir(m) catch; continue end
        println("  [", s, "] ", m.name, " file=", basename(String(m.file)),
                " module=", m.module, " hasbox=", any(expr_has_box, ci.code))
    end
end
# Show the lowered code of the outer function to see if a Box exists at all
println()
println(Base.uncompressed_ir(first(methods(Octopus._u18_box_plain))).code)
