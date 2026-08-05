using Octopus
mk(n) = Phase6DRep([1.0e-3*i for i in 1:n], zeros(n), zeros(n), zeros(n), zeros(n), zeros(n))
d(L) = ElementSpec{:drift}(; L=L, tracking_method=Symplectic6DMap())
# A kills |x|>1.5e-3, B kills |x|>2.5e-3, C kills |x|>3.5e-3, in that order.
A = ApertureSpec(shape=:rectangle, x_limit=1.5e-3, y_limit=1.0, name="A")
B = ApertureSpec(shape=:rectangle, x_limit=2.5e-3, y_limit=1.0, name="B")
C = ApertureSpec(shape=:rectangle, x_limit=3.5e-3, y_limit=1.0, name="C")
line = (d(1.0), A, d(2.0), B, d(3.0), C)
t = TrackingTask(line; policy=CPUThreadsExecutionPolicy(threads=1), loss_report=false)
r = mk(5)     # x = 1,2,3,4,5 mm
execute!(t, r; turns=1)
rec = loss_record(t)
println("aperture order  : ", aperture_names(rec))
println("aperture s      : ", Octopus._aperture_s_positions(t.elements))
println("counts          : ", loss_counts(rec))
println("expected counts : [1(A: 2mm..), ...] -> A kills x=2..5mm (4), B/C get nothing")
println("survivors x     : ", filter(isfinite, r.x))
