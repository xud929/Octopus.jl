# Machine description stage 2 (2026-11-25): the LinearOptics expression-tree measurement behind the
# by-name refusal `_optics_expression_refusal` (src/knowledge/LinearOptics.jl) and the stage's decision
# rule (docs/history/machine_description_stage2_2026_11_25.md: a LinearOptics component may be a knob
# expression only while the trees its flattening builds stay small, a mean of at most 8 nodes per tree,
# and cheap, their evaluation at most 10x the numeric build). With the fold arithmetic the friendly
# constructors use (`Octopus._knob_arith`, design D10) it builds the trees a point would carry into its
# consumers if a component were a knob expression, mirroring the source's own formulas:
#   (1) one knob in beta[1] of the first point of a Linear6DSpec(o1, o2) transfer, the uncoupled 2x2
#       Twiss blocks of src/elements/linear6d.jl (`_mset` lines): how many of the 36 matrix entries
#       become trees, their node counts, and the cost of evaluating the 36 entries through knob_value
#       against the numeric build (1000 repetitions, best of 5; the ratio varies by machine, the node
#       counts do not);
#   (2) one knob in R of a point: the four Edwards-Teng block entries C = adj(R) / sqrt(1 + det R) of
#       `_edwards_teng_block` (linear6d.jl), lambda = inv(sqrt(1 + r1*r4 - r2*r3)), as trees.
# Run from the project root (a minute after precompilation):
#     julia --project=. docs/history/machine_description_stage2_2026_11_25_optics_trees.jl
# A node is one KnobRef, KnobConst or KnobCall; a plain number folded into a tree is a KnobConst.
using Octopus

const K = Octopus._knob_arith
nodes(n::Octopus.KnobCall) = 1 + sum(nodes, n.args)
nodes(::Octopus.KnobRef) = 1
nodes(::Octopus.KnobConst) = 1
nodes(::Number) = 0

@knob optics_trees.beta = 10.0
@knob optics_trees.r1 = 0.01

# (1) The 6x6 transfer between two points with beta1[1] a knob. The data are `const` so that the
# numeric build is the type-stable loop the element's constructor runs, not a global-variable walk.
const beta1 = (@knob_expr(optics_trees.beta), 12.0, 3.0); const beta2 = (11.0, 13.0, 3.5)
const alpha1 = (0.1, -0.2, 0.0); const alpha2 = (0.3, 0.1, 0.0); const dmu = (0.7, 1.1, 0.02)
const entries = Any[i == j ? 1.0 : 0.0 for i in 1:6, j in 1:6]
for i in 1:3
    s = sin(dmu[i]); c = cos(dmu[i]); row = 2i - 1
    entries[row, row]         = K(:*, K(:sqrt, K(:/, beta2[i], beta1[i])), c + alpha1[i] * s)
    entries[row, row + 1]     = K(:*, K(:sqrt, K(:*, beta2[i], beta1[i])), s)
    entries[row + 1, row]     = K(:/, (-(1 + alpha1[i] * alpha2[i]) * s + (alpha1[i] - alpha2[i]) * c),
                                  K(:sqrt, K(:*, beta1[i], beta2[i])))
    entries[row + 1, row + 1] = K(:*, K(:sqrt, K(:/, beta1[i], beta2[i])), c - alpha2[i] * s)
end
function numeric_build(b11)
    bb1 = (b11, 12.0, 3.0)
    m = zeros(6, 6)
    for i in 1:6; m[i, i] = 1.0; end
    for i in 1:3
        s = sin(dmu[i]); c = cos(dmu[i]); row = 2i - 1
        m[row, row] = sqrt(beta2[i] / bb1[i]) * (c + alpha1[i] * s)
        m[row, row + 1] = sqrt(beta2[i] * bb1[i]) * s
        m[row + 1, row] = (-(1 + alpha1[i] * alpha2[i]) * s + (alpha1[i] - alpha2[i]) * c) / sqrt(bb1[i] * beta2[i])
        m[row + 1, row + 1] = sqrt(bb1[i] / beta2[i]) * (c - alpha2[i] * s)
    end
    return m
end
eval_trees() = map(knob_value, entries)
const trees = [e for e in entries if e isa AbstractKnobExpression]
const counts = map(nodes, trees)
numeric_build(10.0); eval_trees()   # compile both before timing
t_num = minimum(@elapsed(for _ in 1:1000; numeric_build(10.0); end) for _ in 1:5)
t_tree = minimum(@elapsed(for _ in 1:1000; eval_trees(); end) for _ in 1:5)
println("MATRIX: ", length(trees), " of 36 entries are trees; nodes per tree ", counts, "; total ", sum(counts),
        "; mean over trees ", sum(counts) / length(trees), "; mean over 36 entries ", round(sum(counts) / 36; digits=3),
        "; max ", maximum(counts))
println("MATRIX: trees evaluate to the numeric build at the knob's value: ", eval_trees() == numeric_build(10.0))
println("MATRIX: knob_value over the 36 entries ", round(1e6 * t_tree / 1000; digits=3), " us; numeric build ",
        round(1e6 * t_num / 1000; digits=3), " us; ratio ", round(t_tree / t_num; digits=1), "x")
foreach(t -> println("MATRIX tree: ", t), trees)

# (2) The Edwards-Teng block of one point with r1 a knob: lambda shared by the four entries.
r1, r2, r3, r4 = (@knob_expr(optics_trees.r1), 0.02, -0.01, 0.03)
lambda = K(:inv, K(:sqrt, K(:-, K(:+, 1, K(:*, r1, r4)), K(:*, r2, r3))))
block = (K(:*, lambda, r4), K(:*, K(:-, lambda), r2), K(:*, K(:-, lambda), r3), K(:*, lambda, r1))
println("EDWARDS-TENG: nodes per entry ", map(nodes, block), "; total ", sum(map(nodes, block)),
        "; normalizer lambda alone ", nodes(lambda))
println("EDWARDS-TENG: block evaluates to the numeric formula: ",
        map(knob_value, block) == (inv(sqrt(1 + 0.01 * r4 - r2 * r3)) .* (r4, -r2, -r3, 0.01)))
println("EDWARDS-TENG entry 1: ", block[1])
