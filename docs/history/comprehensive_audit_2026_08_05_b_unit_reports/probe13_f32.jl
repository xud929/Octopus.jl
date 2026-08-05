using Octopus, Printf
const O = Octopus
println("CPU weight element types for Float32 input:")
for u in (Float32(3.3), Float32(3.7))
    b, w = O._pic_tsc_weights(u, 16); @printf("  _pic_tsc_weights(%s::Float32, 16) -> eltype(w) = %s\n", u, eltype(w))
    b, w = O._pic_cic_weights(u, 16); @printf("  _pic_cic_weights(%s::Float32, 16) -> eltype(w) = %s\n", u, eltype(w))
end
c = zeros(Float32, 32, 32)
x = Float32[1.0f-4*sin(0.7f0*i) for i in 1:100]; y = Float32[1.0f-5*sin(0.31f0*i) for i in 1:100]
O._pic_deposit_serial!(c, :TSC, x, y, -2.0f-4, -2.0f-5, Float32(4e-4/15), Float32(4e-5/15), 16, 16)
@printf("Float32 charge array after a TSC deposit: eltype=%s, sum=%.9g\n", eltype(c), sum(c))
