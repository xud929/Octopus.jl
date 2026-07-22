export CLIGHT, RE, ME0, EMASS_EV, PMASS_EV, TWOPI, SQRT2PI, SQRTPI, SQRT2

"""
    CLIGHT

Speed of light in vacuum, in meters per second.
"""
const CLIGHT = 299_792_458.0

"""Classical electron radius in meters (2022 CODATA)."""
const RE = 2.8179403205e-15

"""Electron rest energy in eV (2022 CODATA)."""
const EMASS_EV = 0.51099895069e6

"""Compatibility alias for [`EMASS_EV`](@ref)."""
const ME0 = EMASS_EV

"""Proton rest energy in eV (2022 CODATA)."""
const PMASS_EV = 938.27208943e6

"""2π."""
const TWOPI = 6.283185307179586476925286766559005768394338

"""√(2π)."""
const SQRT2PI = 2.506628274631000502415765284811045253006964

"""√π."""
const SQRTPI = 1.772453850905516027298167483341145182797554

"""√2."""
const SQRT2 = 1.414213562373095048801688724209698078569662
