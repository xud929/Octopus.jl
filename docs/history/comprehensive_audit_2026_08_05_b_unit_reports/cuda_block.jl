if Octopus._HAS_CUDA && Octopus.CUDA.functional()
    function cuda_round_gaussian_near_axis_kernel!(output, sigma, x, y)
        kx, ky = Octopus._cuda_gaussian_beambeam_kick(sigma, sigma, x, y)
        r2 = x * x + y * y
        expterm = exp(-r2 / (2 * sigma * sigma))
        hxx, hxy, hyy =
            Octopus._round_gaussian_hessian(one(sigma), sigma, x, y, expterm)
        output[1] = kx
        output[2] = ky
        output[3] = hxx
        output[4] = hxy
        output[5] = hyy
        return nothing
    end

    function cuda_near_round_gaussian_kernel!(output, sig1, sig2, x, y)
        Kx, Ky, H1, H2 = Octopus._cuda_gaussian_beambeam_kick_response(
            one(sig1), sig1, sig2, x, y)
        output[1] = Kx
        output[2] = Ky
        output[3] = H1
        output[4] = H2
        return nothing
    end

    @testset "CUDA round Gaussian near-axis stability" begin
        for (T, x, y) in (
                (Float32, 1.0f-4, -5.0f-5),
                (Float64, 1.0e-8, -5.0e-9))
            sigma = one(T)
            expected_kick = gaussian_beambeam_kick(sigma, sigma, x, y)
            expterm = exp(-(x * x + y * y) / (2 * sigma * sigma))
            expected_hessian =
                Octopus._round_gaussian_hessian(one(T), sigma, x, y, expterm)
            output = Octopus.CUDA.zeros(T, 5)
            Octopus.CUDA.@cuda threads=1 blocks=1 cuda_round_gaussian_near_axis_kernel!(
                output, sigma, x, y)
            Octopus.CUDA.synchronize()
            actual = Array(output)
            expected = T[expected_kick..., expected_hessian...]
            @test actual ≈ expected rtol=16eps(T) atol=16eps(T)
            @test actual[1] != zero(T)
            @test actual[2] != zero(T)
        end
    end

    @testset "CUDA near-round Gaussian transition matches CPU" begin
        for T in (Float32, Float64)
            inner, outer = Octopus._near_round_eta_bounds(zero(T))
            tolerance = T === Float32 ? 3.0e-5 : 3.0e-11
            for eta in (inner, T(0.75) * outer, outer, T(1.2) * outer, T(0.1))
                sig1, sig2 = sqrt(one(T) + eta), sqrt(one(T) - eta)
                for (x, y) in (
                        (T(1.0e-6), T(-5.0e-7)),
                        (T(0.2), T(-0.1)),
                        (T(1.3), T(0.7)),
                        (sqrt(T(0.0625)) * cos(T(pi / 16)),
                         sqrt(T(0.0625)) * sin(T(pi / 16))),
                        (sqrt(T(5)) * cos(T(15pi / 32)),
                         sqrt(T(5)) * sin(T(15pi / 32))))
                    expected = Octopus._gaussian_beambeam_kick_response(
                        one(T), sig1, sig2, x, y)
                    output = Octopus.CUDA.zeros(T, 4)
                    Octopus.CUDA.@cuda threads=1 blocks=1 cuda_near_round_gaussian_kernel!(
                        output, sig1, sig2, x, y)
                    Octopus.CUDA.synchronize()
                    @test Array(output) ≈ collect(expected) rtol=tolerance atol=tolerance
                end
            end
        end
    end

    @testset "CUDA strong-strong shifted moments preserve small spreads" begin
        for T in (Float32, Float64)
            n = 8192
            offset = T === Float32 ? T(1.0e4) : T(1.0e8)
            x = offset .+ repeat(T[-1, 1, -1, 1], n ÷ 4)
            px = -T(2) * offset .+ repeat(T[2, -2, 2, -2], n ÷ 4)
            y = T(3) * offset .+ repeat(T[-3, 3, -3, 3], n ÷ 4)
            py = -T(4) * offset .+ repeat(T[4, -4, 4, -4], n ÷ 4)
            z = zeros(T, n)
            rep = Phase6DRep(
                Octopus.CUDA.CuArray(x), Octopus.CUDA.CuArray(px),
                Octopus.CUDA.CuArray(y), Octopus.CUDA.CuArray(py),
                Octopus.CUDA.CuArray(z), Octopus.CUDA.CuArray(z))
            idx = Octopus.CUDA.CuArray(collect(1:n))
            launch = Octopus._cuda_gaussian_moment_launch(n)

            for coupled in (false, true)
                coupling = Val(coupled)
                partials = Octopus.CUDA.CuArray{T}(undef,
                    Octopus._cuda_gaussian_moment_nstats(coupling),
                    launch.blocks, 1)
                moments = Octopus._cuda_slice_transverse_moments(
                    rep, idx, partials, false, zero(T), coupling)
                @test moments.mx ≈ offset
                @test moments.moments.a0 ≈ T(1)
                @test moments.moments.d0 ≈ T(9)
                @test moments.moments.bxx ≈ -T(2)
                @test moments.moments.bypy ≈ -T(12)
                @test moments.moments.qxx ≈ T(4)
                @test moments.moments.qyy ≈ T(16)
                if coupled
                    @test moments.moments.b0 ≈ T(3)
                    @test moments.moments.bxpy ≈ -T(4)
                    @test moments.moments.bypx ≈ -T(6)
                    @test moments.moments.qxy ≈ T(8)
                end
            end

            gpic = Octopus._cuda_gpic_source_moments(
                (x=rep.x, px=rep.px, y=rep.y, py=rep.py))
            @test gpic.mx ≈ offset
            @test gpic.varx ≈ T(1)
            @test gpic.cxpx ≈ -T(2)
            @test gpic.vary ≈ T(9)
            @test gpic.cypy ≈ -T(12)
        end

        # Exercise the separate fused wavefront moment kernel through its solver.
        n = 1024
        offset = 1.0e8
        x = offset .+ repeat([-1.0, -1.0, 1.0, 1.0], n ÷ 4)
        px = 2offset .+ repeat([-3.0, 3.0, -3.0, 3.0], n ÷ 4)
        y = -offset .+ repeat([-2.0, 2.0, -2.0, 2.0], n ÷ 4)
        py = -2offset .+ repeat([4.0, 4.0, -4.0, -4.0], n ÷ 4)
        z = zeros(n)
        host_rep() = Phase6DRep(
            copy(x), copy(px), copy(y), copy(py), copy(z), copy(z))
        gpu_rep() = Phase6DRep(
            (Octopus.CUDA.CuArray(a) for a in coordinate_arrays(host_rep()))...)
        params = BeamParams{Float64}(
            charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
        cpu_beam(rep) =
            Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
        gpu_beam(rep) =
            Beam{Octopus.CUDABackend,typeof(params),typeof(rep)}(params, rep)
        solver = GaussianPoissonSolver(
            kbb1=0.0, kbb2=0.0, luminosity_scale=1.0,
            slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
            longitudinal_kick=false, batch_mode=:wavefront)
        cpu1 = cpu_beam(host_rep()); cpu2 = cpu_beam(host_rep())
        gpu1 = gpu_beam(gpu_rep()); gpu2 = gpu_beam(gpu_rep())
        cpu_luminosity = collide!(solver, cpu1, cpu2, CPUThreadsBackend)
        gpu_luminosity = collide!(solver, gpu1, gpu2, Octopus.CUDABackend)
        Octopus.CUDA.synchronize()
        @test isfinite(cpu_luminosity)
        @test gpu_luminosity ≈ cpu_luminosity rtol=2.0e-12
    end

    @testset "CUDA PIC field_derivative matches CPU" begin
        # The flag is consumed by three separate CUDA kernels (single, batched,
        # wavefront). Check parity for BOTH settings so a divergence in any of
        # them is caught, and check that :fourth actually changes the CUDA result.
        mkpair(backend) = begin
            set_global_rng!(seed=77, method=:philox)
            e = Beam(6000, backend, Float64; beta=(0.55, 0.056, 12.0),
                alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
                rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(6000, backend, Float64; beta=(0.8, 0.072, 90.0),
                alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
                rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            return e, p
        end
        sl = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        results = Dict{Symbol,Any}()
        for fd in (:second, :fourth), (name, backend, policy) in
                ((:cpu, CPUThreadsBackend, CPUThreadsBackend), (:gpu, CUDABackend, CUDAExecutionPolicy()))
            e, p = mkpair(policy)
            lum = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), field_derivative=fd),
                           e, p, backend)
            results[Symbol(fd, :_, name)] = (lum, flat(e), flat(p))
        end
        for fd in (:second, :fourth)
            (lc, ec, pc) = results[Symbol(fd, :_cpu)]
            (lg, eg, pg) = results[Symbol(fd, :_gpu)]
            @test isapprox(ec, eg; rtol=1e-11, atol=1e-14)
            @test isapprox(pc, pg; rtol=1e-11, atol=1e-14)
            @test isapprox(lc, lg; rtol=1e-11)
        end
        @test results[:second_gpu][2] != results[:fourth_gpu][2]   # flag reaches CUDA
    end

    @testset "CUDA PIC slice_interpolation matches CPU" begin
        # :quadratic runs on the sequential non-async route and, via its own
        # 6-planes-per-pair path, on the batched-FFT routes including the
        # production indexed wavefront. Check parity for both settings on every
        # supported route, that the flag changes the CUDA result, and that the
        # one route which cannot carry a third field plane (non-batched async)
        # throws instead of silently dropping it.
        mkpair(backend) = begin
            set_global_rng!(seed=31, method=:philox)
            e = Beam(4000, backend, Float64; beta=(0.55, 0.056, 12.0),
                alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
                rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(4000, backend, Float64; beta=(0.8, 0.072, 90.0),
                alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
                rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            return e, p
        end
        sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        base = (; slicing=sl, grid=(32, 32), batch_mode=:sequential, cuda_async=false)
        res = Dict{Symbol,Any}()
        for si in (:linear, :quadratic), (name, backend, policy) in
                ((:cpu, CPUThreadsBackend, CPUThreadsBackend), (:gpu, CUDABackend, CUDAExecutionPolicy()))
            e, p = mkpair(policy)
            lum = collide!(PICPoissonSolver(; base..., slice_interpolation=si), e, p, backend)
            res[Symbol(si, :_, name)] = (lum, flat(e), flat(p))
        end
        for si in (:linear, :quadratic)
            (lc, ec, pc) = res[Symbol(si, :_cpu)]
            (lg, eg, pg) = res[Symbol(si, :_gpu)]
            @test isapprox(ec, eg; rtol=1e-11, atol=1e-14)
            @test isapprox(pc, pg; rtol=1e-11, atol=1e-14)
            @test isapprox(lc, lg; rtol=1e-11)
        end
        @test res[:linear_gpu][2] != res[:quadratic_gpu][2]   # flag reaches CUDA

        # The batched-FFT routes carry the midpoint plane via their own 6-plane
        # path (planes L/M/R per direction with a per-plane Green stack). The
        # production indexed wavefront, the gathered wavefront, and the
        # sequential batched-FFT sub-route must all match the CPU :quadratic
        # result.
        let ref = res[:quadratic_cpu]
            for kw in ((; batch_mode=:wavefront),
                       (; batch_mode=:wavefront, cuda_indexed_wavefront=false),
                       (; batch_mode=:sequential, cuda_async=true))
                eg, pg = mkpair(CUDAExecutionPolicy())
                lum = collide!(PICPoissonSolver(; slicing=sl, grid=(32, 32),
                                                slice_interpolation=:quadratic, kw...),
                               eg, pg, CUDABackend)
                @test isapprox(ref[2], flat(eg); rtol=1e-11, atol=1e-14)
                @test isapprox(ref[3], flat(pg); rtol=1e-11, atol=1e-14)
                @test isapprox(ref[1], lum; rtol=1e-11)
            end
        end
        # The non-batched async route still carries only two planes per
        # direction and must refuse :quadratic, as must the non-async wavefront
        # combination (which never had a third-plane path).
        for kw in ((; batch_mode=:wavefront, cuda_async=false),
                   (; batch_mode=:wavefront, cuda_batch_fft=false),
                   (; batch_mode=:sequential, cuda_async=true, cuda_batch_fft=false))
            e, p = mkpair(CUDAExecutionPolicy())
            @test_throws ArgumentError collide!(
                PICPoissonSolver(; slicing=sl, grid=(32, 32), slice_interpolation=:quadratic,
                                 kw...), e, p, CUDABackend)
        end
        # interaction_grid=:source_slice is CPU-only on every CUDA route.
        let (e, p) = mkpair(CUDAExecutionPolicy())
            @test_throws ArgumentError collide!(
                PICPoissonSolver(; slicing=sl, grid=(32, 32), interaction_grid=:source_slice),
                e, p, CUDABackend)
        end

        # interaction_grid=:node is implemented on the sequential non-async route.
        nres = Dict{Symbol,Any}()
        for (name, backend, policy) in
                ((:cpu, CPUThreadsBackend, CPUThreadsBackend), (:gpu, CUDABackend, CUDAExecutionPolicy()))
            e, p = mkpair(policy)
            lum = collide!(PICPoissonSolver(; base..., interaction_grid=:node), e, p, backend)
            nres[name] = (lum, flat(e), flat(p))
        end
        @test isapprox(nres[:cpu][2], nres[:gpu][2]; rtol=1e-11, atol=1e-14)
        @test isapprox(nres[:cpu][3], nres[:gpu][3]; rtol=1e-11, atol=1e-14)
        @test isapprox(nres[:cpu][1], nres[:gpu][1]; rtol=1e-11)
        @test nres[:gpu][2] != res[:linear_gpu][2]      # reaches the CUDA consumer

        # :node runs on the indexed wavefront route via its own 6-plane path, and
        # on the sequential non-async route. Both must match CPU.
        let ref = nothing
            e, p = mkpair(CPUThreadsBackend)
            collide!(PICPoissonSolver(; slicing=sl, grid=(32, 32), interaction_grid=:node),
                     e, p, CPUThreadsBackend)
            ref = flat(e)
            for kw in ((; batch_mode=:wavefront), (; batch_mode=:wavefront, cuda_async=true),
                       (; batch_mode=:sequential, cuda_async=false))
                eg, pg = mkpair(CUDAExecutionPolicy())
                collide!(PICPoissonSolver(; slicing=sl, grid=(32, 32),
                                          interaction_grid=:node, kw...), eg, pg, CUDABackend)
                @test isapprox(ref, flat(eg); rtol=1e-11, atol=1e-14)
            end
        end
        # The sequential batched-FFT sub-route still assumes one mesh per slice
        # pair and must refuse :node rather than silently using the wrong mesh.
        let (e, p) = mkpair(CUDAExecutionPolicy())
            @test_throws ArgumentError collide!(
                PICPoissonSolver(; slicing=sl, grid=(32, 32), interaction_grid=:node,
                                 batch_mode=:sequential, cuda_async=true), e, p, CUDABackend)
        end
    end

    function test_gpu_beam(x, y)
        n = length(x)
        rep = Phase6DRep(
            Octopus.CUDA.CuArray(x), Octopus.CUDA.zeros(Float64, n),
            Octopus.CUDA.CuArray(y), Octopus.CUDA.zeros(Float64, n),
            Octopus.CUDA.zeros(Float64, n), Octopus.CUDA.zeros(Float64, n),
        )
        params = BeamParams{Float64}(
            charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n,
        )
        return Beam{Octopus.CUDABackend,typeof(params),typeof(rep)}(params, rep)
    end

    @testset "CUDA solver workspaces are exclusive and device-aware" begin
        device = Int(Octopus.CUDA.deviceid(Octopus.CUDA.device()))
        @test Octopus._spectral_cuda_cache_key(
            Float64, 16, 24, device) !=
              Octopus._spectral_cuda_cache_key(
                  Float64, 16, 24, device + 1)
        lease1 = Octopus._acquire_spectral_cuda_ws(Float64, 16, 24)
        lease2 = Octopus._acquire_spectral_cuda_ws(Float64, 16, 24)
        try
            @test lease1 !== lease2
            @test lease1.workspace !== lease2.workspace
            @test lease1.device == device
            @test lease2.device == device
            @test Int(Octopus.CUDA.deviceid(
                Octopus.CUDA.device(lease1.workspace.rho))) == device
        finally
            Octopus._release_spectral_cuda_ws!(lease1)
            Octopus._release_spectral_cuda_ws!(lease2)
        end

        cache = Dict{Any,Any}()
        pic = PICPoissonSolver(grid=(16, 16))
        Octopus._cuda_pic_workspace!(
            cache, :device_key_test, pic, Float64)
        key = only(keys(cache))
        @test key[1] === :cuda_pic_workspace
        @test key[3] == device
    end

    @testset "CUDA PIC wavefront workspace cache is capacity bounded" begin
        solver = PICPoissonSolver(grid=(16, 24))
        workspace = Octopus._cuda_pic_workspace(solver, Float64)
        batches = [collect(1:n) for n in (1, 3, 2)]

        Octopus._cuda_pic_reserve_wavefront_workspaces!(
            workspace, solver, Float64, batches,
        )
        @test collect(keys(workspace.wavefront_cache)) == [:standard]
        standard = workspace.wavefront_cache[:standard]
        @test standard.capacity == 12
        @test size(standard.arrays.charges) == (32, 48, 12)

        small = Octopus._cuda_pic_wavefront_workspace!(
            workspace, solver, Float64, 4,
        )
        @test size(small.charges) == (32, 48, 4)
        @test size(small.green_spectral) == (32, 48, 2)
        @test pointer(small.charges) == pointer(standard.arrays.charges)
        @test workspace.wavefront_cache[:standard] === standard
        @test length(workspace.wavefront_cache) == 1

        Octopus._cuda_pic_reserve_wavefront_workspaces!(
            workspace, solver, Float64, batches; node=true,
        )
        @test Set(keys(workspace.wavefront_cache)) == Set((:standard, :node))
        node = workspace.wavefront_cache[:node]
        @test node.capacity == 18
        node_small = Octopus._cuda_pic_wavefront_node_workspace!(
            workspace, solver, Float64, 6,
        )
        @test size(node_small.charges) == (32, 48, 6)
        @test pointer(node_small.charges) == pointer(node.arrays.charges)
        @test_throws ArgumentError Octopus._cuda_pic_wavefront_workspace!(
            workspace, solver, Float64, 6,
        )
        @test_throws ArgumentError Octopus._cuda_pic_wavefront_node_workspace!(
            workspace, solver, Float64, 4,
        )
    end

    @testset "CUDA spectral solver matches CPU" begin
        function to_gpu(b)
            rep = Phase6DRep(
                (Octopus.CUDA.CuArray(copy(a)) for a in coordinate_arrays(b.rep))...)
            return Beam{Octopus.CUDABackend,typeof(b.params),typeof(rep)}(b.params, rep)
        end
        function flat_pair()
            set_global_rng!(seed=11, method=:philox)
            e = Beam(4000, CPUThreadsBackend, Float64;
                beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 1.0e-2), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(4000, CPUThreadsBackend, Float64;
                beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 1.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=1.7e11)
            return e, p
        end
        sl = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)
        # Cover both the transverse-only map and the full 6D synchro-beam map (the
        # latter exercises the potential/pz path on both backends).
        for longitudinal_kick in (false, true)
            solver = SpectralPoissonSolver(slicing=sl, method=:grid, grid=(64, 512),
                                           domain_factor=16.0,
                                           longitudinal_kick=longitudinal_kick)
            ecpu, pcpu = flat_pair()
            egpu, pgpu = to_gpu(ecpu), to_gpu(pcpu)
            lum_cpu = collide!(solver, ecpu, pcpu, CPUThreadsBackend)
            lum_gpu = collide!(solver, egpu, pgpu, Octopus.CUDABackend)
            Octopus.CUDA.synchronize()
            # Same algorithm and particle data, so CPU and CUDA agree to round-off
            # (up to accumulation order across the backends' parallel reductions).
            for (cpu_beam, gpu_beam) in ((ecpu, egpu), (pcpu, pgpu))
                for (expected, actual) in zip(coordinate_arrays(cpu_beam),
                                              coordinate_arrays(gpu_beam))
                    @test Array(actual) ≈ expected rtol=1.0e-9 atol=1.0e-18
                end
            end
            @test lum_gpu ≈ lum_cpu rtol=1.0e-9
        end
        # field_precision=:single runs the CUDA field solve in Float32: not
        # bit-parity with the CPU Float64 path, but the smooth field keeps the kick
        # accurate to ~1e-6 (well under the ~1% physics floor).
        single = SpectralPoissonSolver(slicing=sl, method=:grid, grid=(64, 512),
                                       domain_factor=16.0, longitudinal_kick=true,
                                       field_precision=:single)
        ecpu, pcpu = flat_pair(); egpu, pgpu = to_gpu(ecpu), to_gpu(pcpu)
        collide!(single, ecpu, pcpu, CPUThreadsBackend)
        collide!(single, egpu, pgpu, Octopus.CUDABackend); Octopus.CUDA.synchronize()
        for (cpu_beam, gpu_beam) in ((ecpu, egpu), (pcpu, pgpu))
            for (expected, actual) in zip(coordinate_arrays(cpu_beam),
                                          coordinate_arrays(gpu_beam))
                @test Array(actual) ≈ expected rtol=1.0e-5 atol=1.0e-16
            end
        end
        # grid-free is CPU-only on CUDA
        gf = SpectralPoissonSolver(slicing=sl, method=:grid_free, grid=(48, 48),
                                   longitudinal_kick=false)
        ecpu, pcpu = flat_pair()
        egpu, pgpu = to_gpu(ecpu), to_gpu(pcpu)
        @test_throws ArgumentError collide!(gf, egpu, pgpu, Octopus.CUDABackend)
    end

    @testset "CUDA spectral deposit tripwire (R9, U9-1)" begin
        # Kernel-level: one fully-out-of-box particle among in-box ones leaves
        # exactly its unit charge in ws.dropped, for each of the three deposit
        # kernels. The negative control must be exactly 0.0, not merely small:
        # the clipped weight is a subset-sum difference in matching term
        # order, so a fully-deposited particle contributes nothing at all.
        lease = Octopus._acquire_spectral_cuda_ws(Float64, 16, 16)
        ws = lease.workspace
        try
            n = 64
            sx = Octopus.CUDA.CuArray([fill(1.0e-4, n - 1); 5.0e-3])
            sy = Octopus.CUDA.zeros(Float64, n)
            spx = Octopus.CUDA.zeros(Float64, n)
            spy = Octopus.CUDA.zeros(Float64, n)
            Lx = Ly = 1.0e-3
            dropped() = Array(ws.dropped)[1]
            Octopus.CUDA.fill!(ws.dropped, 0.0)
            Octopus._cuda_spectral_field!(ws, sx, sy, Lx, Ly)
            @test dropped() ≈ 1.0 atol = 1.0e-12
            Octopus.CUDA.fill!(ws.dropped, 0.0)
            Octopus._cuda_spectral_potential_solve!(
                ws, ws.PhigL, ws.ExgL, ws.EygL, sx, spx, sy, spy, 0.0, Lx, Ly)
            @test dropped() ≈ 1.0 atol = 1.0e-12
            idx = Octopus.CUDA.CuArray(collect(1:n))
            Octopus.CUDA.fill!(ws.dropped, 0.0)
            Octopus._cuda_spectral_potential_solve_idx!(
                ws, ws.PhigL, ws.ExgL, ws.EygL, sx, spx, sy, spy, idx, 0.0, Lx, Ly)
            @test dropped() ≈ 1.0 atol = 1.0e-12
            inside = Octopus.CUDA.CuArray(fill(1.0e-4, n))
            Octopus.CUDA.fill!(ws.dropped, 0.0)
            Octopus._cuda_spectral_field!(ws, inside, sy, Lx, Ly)
            @test dropped() == 0.0
        finally
            Octopus._release_spectral_cuda_ws!(lease)
        end

        # Collide-level: the CPU R9 configuration (box sized once from
        # pre-collision coordinates, strong intra-collision kick; the CPU
        # twin of this assert is in the slicing testset) warns through the
        # CUDA 6D path too -- one aggregate warning per collision where the
        # CPU path warns per solve. No transverse-path assert: that map never
        # moves x/y inside the collision, so its deposits cannot clip.
        strong_gpu(n) = begin
            s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
            x = s(1.0e-4, 0.0); x[1] = 8.0e-4
            rep = Phase6DRep((Octopus.CUDA.CuArray(a) for a in
                (x, s(1.0e-5, 0.3), s(1.0e-4, 0.9), s(1.0e-5, 1.2),
                 s(1.0e-2, 2.0), s(1.0e-4, 2.5)))...)
            params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
            Beam{Octopus.CUDABackend,typeof(params),typeof(rep)}(params, rep)
        end
        sp64 = SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
            grid=(64, 64), slicing=LongitudinalSlicing(nslices=2, method=:equal_count))
        @test_logs (:warn, r"clipped charge at the Dirichlet wall") match_mode = :any collide!(
            sp64, strong_gpu(256), strong_gpu(256), Octopus.CUDABackend)
    end

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

    @testset "CUDA GaussianPIC solver matches CPU" begin
        to_gpu(b) = begin
            rep = Phase6DRep((Octopus.CUDA.CuArray(copy(a)) for a in coordinate_arrays(b.rep))...)
            Beam{Octopus.CUDABackend,typeof(b.params),typeof(rep)}(b.params, rep)
        end
        function gp_pair()
            set_global_rng!(seed=19, method=:philox)
            e = Beam(6000, CPUThreadsBackend, Float64;
                beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(6000, CPUThreadsBackend, Float64;
                beta=(0.8, 0.072, 90.0), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            return e, p
        end
        sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        # Cover the transverse-only and full 6D map, and both CUDA wavefront paths
        # (indexed default, and the non-indexed fallback).
        for longitudinal_kick in (false, true), indexed in (true, false)
            solver = GaussianPICPoissonSolver(slicing=sl, grid=(64, 64), green_cache=:none,
                                              longitudinal_kick=longitudinal_kick,
                                              cuda_indexed_wavefront=indexed)
            ecpu, pcpu = gp_pair()
            egpu, pgpu = to_gpu(ecpu), to_gpu(pcpu)
            lum_cpu = collide!(solver, ecpu, pcpu, CPUThreadsBackend)
            lum_gpu = collide!(solver, egpu, pgpu, Octopus.CUDABackend)
            Octopus.CUDA.synchronize()
            for (cpu_beam, gpu_beam) in ((ecpu, egpu), (pcpu, pgpu))
                for (expected, actual) in zip(coordinate_arrays(cpu_beam),
                                              coordinate_arrays(gpu_beam))
                    # ~1e-13: the only backend difference is the parallel-reduction
                    # order of the slice moments; well within the 1e-10 contract.
                    @test Array(actual) ≈ expected rtol=1.0e-9 atol=1.0e-18
                end
            end
            @test lum_gpu ≈ lum_cpu rtol=1.0e-9
        end
    end

    @testset "CUDA coupled weak-strong parity" begin
        coupling = XYCouplingSpec{Float64}(
            r1=0.08, r2=0.03, r3=-0.02, r4=0.05)
        q = (4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4)
        for virtual_drift in (
                UnsafeVirtualDrift(:chromatic_frozen_energy),
                UnsafeVirtualDrift(:paraxial_frozen_longitudinal),
                :hirata, :chromatic, :exact)
            thin = ThinStrongBeam(ThinStrongBeamSpec(;
                kbb=1.0e-7, beta=(0.8, 1.2), alpha=(0.3, -0.2),
                sigma=(1.1e-3, 0.7e-3), coupling=coupling,
                center=(2.0e-5, -1.0e-5, 3.0e-4),
                angle=(3.0e-4, -2.0e-4, 0.0),
                curvature=(2.0e-3, -1.0e-3, 0.0),
                virtual_drift=virtual_drift))
            expected_thin = thin(q...)
            thin_rep = Phase6DRep(
                (Octopus.CUDA.CuArray([value]) for value in q)...)
            track!(thin_rep, thin, 1, Octopus.CUDABackend; threads=32, blocks=1)
            Octopus.CUDA.synchronize()
            actual_thin = Tuple(
                Array(array)[1] for array in coordinate_arrays(thin_rep))
            @test collect(actual_thin) ≈ collect(expected_thin) rtol=2.0e-14 atol=1.0e-18
        end

        transverse = transverse_covariance(;
            beta=(0.7, 0.9), alpha=(0.1, -0.2), sigma=(1.2e-3, 0.8e-3))
        covariance6 = gaussian_strong_beam_covariance(
            transverse, [4.0e-4 3.0e-5; 3.0e-5 9.0e-6];
            crab_dispersion=(0.12, -0.03, 0.04, 0.02),
            momentum_dispersion=(0.5, 0.1, -0.2, 0.3))
        gaussian = GaussianStrongBeam(GaussianStrongBeamSpec(;
            thin=ThinStrongBeamSpec(kbb=1.0e-7, covariance=transverse),
            ns=3, covariance=covariance6))
        expected_gaussian = gaussian(q...)
        gaussian_rep = Phase6DRep((Octopus.CUDA.CuArray([value]) for value in q)...)
        track!(gaussian_rep, gaussian, 1, Octopus.CUDABackend; threads=32, blocks=1)
        Octopus.CUDA.synchronize()
        actual_gaussian = Tuple(
            Array(array)[1] for array in coordinate_arrays(gaussian_rep))
        @test collect(actual_gaussian) ≈ collect(expected_gaussian) rtol=2.0e-14 atol=1.0e-18
    end

    @testset "CUDA coupled soft-Gaussian wavefront parity" begin
        n = 256
        phase = range(0.0, 2pi; length=n + 1)[1:n]
        arrays1 = (
            1.1e-4 .* sin.(phase), 1.8e-4 .* cos.(2 .* phase),
            8.0e-5 .* cos.(phase) .+ 1.0e-5 .* sin.(3 .* phase),
            1.4e-4 .* sin.(2 .* phase) .- 2.0e-5 .* cos.(phase),
            collect(range(-7.0e-3, 7.0e-3; length=n)),
            5.0e-4 .* cos.(3 .* phase),
        )
        arrays2 = Tuple(reverse(copy(array)) for array in arrays1)
        cpu1 = test_beam(Phase6DRep((copy(array) for array in arrays1)...))
        cpu2 = test_beam(Phase6DRep((copy(array) for array in arrays2)...))
        gpu_rep1 = Phase6DRep((Octopus.CUDA.CuArray(array) for array in arrays1)...)
        gpu_rep2 = Phase6DRep((Octopus.CUDA.CuArray(array) for array in arrays2)...)
        gpu1 = Beam{Octopus.CUDABackend,typeof(cpu1.params),typeof(gpu_rep1)}(
            cpu1.params, gpu_rep1)
        gpu2 = Beam{Octopus.CUDABackend,typeof(cpu2.params),typeof(gpu_rep2)}(
            cpu2.params, gpu_rep2)
        solver = GaussianPoissonSolver(
            kbb1=1.0e-8, kbb2=-8.0e-9, luminosity_scale=1.0,
            slicing=LongitudinalSlicing(nslices=3, method=:equal_count),
            include_sigma_xy=true, virtual_drift=:exact, batch_mode=:wavefront)
        cpu_luminosity = collide!(solver, cpu1, cpu2, CPUThreadsBackend)
        gpu_luminosity = collide!(solver, gpu1, gpu2, Octopus.CUDABackend)
        Octopus.CUDA.synchronize()
        for (cpu_beam, gpu_beam) in ((cpu1, gpu1), (cpu2, gpu2))
            for (expected, actual) in zip(
                    coordinate_arrays(cpu_beam), coordinate_arrays(gpu_beam))
                @test Array(actual) ≈ expected rtol=2.0e-12 atol=2.0e-18
            end
        end
        @test gpu_luminosity ≈ cpu_luminosity rtol=2.0e-12
    end

    @testset "CUDA zero-width PIC routes remain finite" begin
        n = 16
        x = collect(range(-1.0e-3, 1.0e-3; length=n))
        y = reverse(copy(x))
        configurations = (
            (batch_mode=:sequential, cuda_indexed_wavefront=true),
            (batch_mode=:wavefront, cuda_indexed_wavefront=false),
            (batch_mode=:wavefront, cuda_indexed_wavefront=true),
        )
        for configuration in configurations
            beam1 = test_gpu_beam(x, y)
            beam2 = test_gpu_beam(y, x)
            solver = PICPoissonSolver(
                kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
                grid=(16, 16), green_cache=:none, longitudinal_kick=true,
                slicing=LongitudinalSlicing(nslices=1, method=:equal_count);
                configuration...,
            )
            luminosity = collide!(solver, beam1, beam2, Octopus.CUDABackend)
            Octopus.CUDA.synchronize()
            @test isfinite(luminosity)
            @test all(array -> all(isfinite, Array(array)), coordinate_arrays(beam1))
            @test all(array -> all(isfinite, Array(array)), coordinate_arrays(beam2))
        end

        one_particle = test_gpu_beam([0.0], [0.0])
        slices = Octopus._cuda_longitudinal_slices(
            one_particle.rep, LongitudinalSlicing(nslices=3, method=:equal_count),
        )
        @test sum(length, slices.indices) == 1
        @test issorted(slices.boundary)

        gaussian_beam1 = test_gpu_beam([0.0], [0.0])
        gaussian_beam2 = test_gpu_beam([0.0], [0.0])
        gaussian_solver = GaussianPoissonSolver(
            kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0, min_sigma=0.0,
            slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
        )
        gaussian_luminosity = collide!(
            gaussian_solver, gaussian_beam1, gaussian_beam2, Octopus.CUDABackend)
        Octopus.CUDA.synchronize()
        @test gaussian_luminosity == 0.0
        @test all(array -> all(isfinite, Array(array)), coordinate_arrays(gaussian_beam1))
        @test all(array -> all(isfinite, Array(array)), coordinate_arrays(gaussian_beam2))
    end

    @testset "CUDA GaussianPIC singular-reference fallback matches PIC" begin
        n = 64
        x1 = collect(range(-1.0e-3, 1.0e-3; length=n))
        x2 = reverse(copy(x1))
        slicing = LongitudinalSlicing(nslices=1, method=:equal_count)
        common = (
            kbb1=1.0e-4, kbb2=-8.0e-5, luminosity_scale=1.0,
            grid=(16, 16), green_cache=:none, longitudinal_kick=true,
            slicing=slicing,
        )
        gpu_pair(y1, y2) =
            (test_gpu_beam(x1, y1), test_gpu_beam(x2, y2))
        host_arrays(beam) = map(Array, coordinate_arrays(beam))

        # Positive marginal widths but rank-one covariance exercises the default
        # indexed-wavefront mode selected by a finite coupling tolerance.
        pic1, pic2 = gpu_pair(0.75 .* x1, -1.25 .* x2)
        gpic1, gpic2 = gpu_pair(0.75 .* x1, -1.25 .* x2)
        luminosity_pic = collide!(
            PICPoissonSolver(; common...), pic1, pic2, Octopus.CUDABackend)
        luminosity_gpic = collide!(
            GaussianPICPoissonSolver(; common..., coupling_tol=0.0),
            gpic1, gpic2, Octopus.CUDABackend)
        Octopus.CUDA.synchronize()
        @test luminosity_gpic ≈ luminosity_pic rtol=2.0e-12
        for (expected, actual) in zip(host_arrays(pic1), host_arrays(gpic1))
            @test actual ≈ expected rtol=2.0e-12 atol=2.0e-18
        end
        for (expected, actual) in zip(host_arrays(pic2), host_arrays(gpic2))
            @test actual ≈ expected rtol=2.0e-12 atol=2.0e-18
        end

        # A zero marginal width takes the ordinary-PIC fallback on all CUDA
        # routes. The sequential case also verifies that the slice-pair Green
        # cache is forwarded through the fallback.
        route_configs = (
            (batch_mode=:wavefront, cuda_indexed_wavefront=true),
            (batch_mode=:wavefront, cuda_indexed_wavefront=false),
            (batch_mode=:sequential, cuda_indexed_wavefront=true),
        )
        for route in route_configs
            route_common = merge(common, (
                green_cache=:slice_pair,
                min_transverse_extent=(2.0e-3, 2.0e-3),
            ), route)
            pic1, pic2 = gpu_pair(zeros(n), zeros(n))
            gpic1, gpic2 = gpu_pair(zeros(n), zeros(n))
            collide!(
                PICPoissonSolver(; route_common...), pic1, pic2,
                Octopus.CUDABackend)
            collide!(
                GaussianPICPoissonSolver(; route_common...),
                gpic1, gpic2, Octopus.CUDABackend)
            Octopus.CUDA.synchronize()
            for (expected, actual) in zip(host_arrays(pic1), host_arrays(gpic1))
                @test actual ≈ expected rtol=2.0e-12 atol=2.0e-18
            end
            for (expected, actual) in zip(host_arrays(pic2), host_arrays(gpic2))
                @test actual ≈ expected rtol=2.0e-12 atol=2.0e-18
            end
        end
    end

    @testset "CUDA non-finite coordinates fail fast at solver chokepoints" begin
        n = 32
        gpu_rep(; kwargs...) = begin
            host = nonfinite_test_rep(n; kwargs...)
            rep = Phase6DRep((Octopus.CUDA.CuArray(a) for a in coordinate_arrays(host))...)
            params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
            Beam{Octopus.CUDABackend,typeof(params),typeof(rep)}(params, rep)
        end
        sl = LongitudinalSlicing(nslices=2, method=:equal_count)
        pic(; kwargs...) = PICPoissonSolver(; kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
            grid=(16, 16), green_cache=:none, slicing=sl, kwargs...)

        # All three CUDA PIC routes detect a poisoned coordinate. Previously the
        # NaN weight flowed into the atomic deposit and poisoned the whole grid.
        for configuration in (
                (batch_mode=:wavefront, cuda_indexed_wavefront=true),
                (batch_mode=:wavefront, cuda_indexed_wavefront=false),
                (batch_mode=:sequential, cuda_indexed_wavefront=true))
            expect_nonfinite_error(() -> collide!(
                pic(; configuration...), gpu_rep(poison=:x), gpu_rep(), Octopus.CUDABackend))
        end
        # Node interaction grid (wavefront route).
        expect_nonfinite_error(() -> collide!(
            pic(interaction_grid=:node), gpu_rep(poison=:px), gpu_rep(), Octopus.CUDABackend))
        # NaN z is caught at the slicing chokepoint.
        expect_nonfinite_error(() -> collide!(
            pic(), gpu_rep(poison=:z), gpu_rep(), Octopus.CUDABackend))
        # Soft-Gaussian fused wavefront and sequential routes (moment chokepoints).
        for mode in (:wavefront, :sequential)
            gaussian = GaussianPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4,
                luminosity_scale=1.0, slicing=sl, batch_mode=mode)
            expect_nonfinite_error(() -> collide!(
                gaussian, gpu_rep(), gpu_rep(poison=:py, value=Inf), Octopus.CUDABackend))
        end
        # Gaussian-subtracted PIC hybrid (indexed wavefront route).
        gpic = GaussianPICPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
            grid=(16, 16), green_cache=:none, slicing=sl)
        expect_nonfinite_error(() -> collide!(
            gpic, gpu_rep(poison=:px), gpu_rep(), Octopus.CUDABackend))
        # Spectral solver (Dirichlet-box chokepoint).
        spectral = SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
            grid=(16, 16), slicing=sl)
        expect_nonfinite_error(() -> collide!(
            spectral, gpu_rep(poison=:x), gpu_rep(), Octopus.CUDABackend))
    end
end
