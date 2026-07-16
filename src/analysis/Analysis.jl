export PlaceholderAnalysis

"""Placeholder analysis used when no concrete analysis is declared yet."""
struct PlaceholderAnalysis <: AbstractAnalysis end

description(::Type{PlaceholderAnalysis}) = "Placeholder for element analyses not yet implemented."
