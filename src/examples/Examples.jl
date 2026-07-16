export ReferenceExample, BenchmarkExample, ResearchStudyExample

"""
    ReferenceExample(title, summary, objects)

Curated architectural precedent that agents may use as implementation guidance.
"""
struct ReferenceExample <: AbstractExample
    title::String
    summary::String
    objects::Vector{DataType}
end

"""
    BenchmarkExample(title, summary, objects)

Performance or scaling example associated with a set of architectural objects.
"""
struct BenchmarkExample <: AbstractExample
    title::String
    summary::String
    objects::Vector{DataType}
end

"""
    ResearchStudyExample(title, summary, objects)

Research-oriented example. These are useful context but should be treated as
less normative than `ReferenceExample`.
"""
struct ResearchStudyExample <: AbstractExample
    title::String
    summary::String
    objects::Vector{DataType}
end
