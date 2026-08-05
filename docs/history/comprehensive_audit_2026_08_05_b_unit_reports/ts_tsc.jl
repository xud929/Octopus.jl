    @testset "TSC weights are bit-identical across backends (U2-3)" begin
        # The CUDA kernel once derived w3 = 1 - w1 - w2 while the CPU uses
        # the closed form — a 1-ulp backend divergence in a deposit both
        # sides must agree on. The kernel helper is pure arithmetic, so it
        # is compared on the host, both branches and the edges included.
        mismatches = 0
        for n in (16, 33)
            for u in vcat(collect(range(0.0, n - 1.0; length=257)),
                          [0.5, 1.5, 7.25, 7.5, 7.75, n - 1.5, n - 1.0])
                base_cpu, w_cpu = Octopus._pic_tsc_weights(u, n)
                base_gpu, w1, w2, w3 = Octopus._cuda_pic_tsc_weights(u, Int32(n))
                (Int(base_gpu) == base_cpu && (w1, w2, w3) === w_cpu) ||
                    (mismatches += 1)
            end
        end
        @test mismatches == 0
    end
