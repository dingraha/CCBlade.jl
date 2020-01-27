mutable struct Foo{T}
    a::T
    b::Int64
    c::T
end

# https://discourse.julialang.org/t/how-to-write-a-fast-loop-through-structure-fields/22535
# function struct2array!(a::AbstractArray{T}, dt::DT, i::Int) where {T, DT}
#     assignments = Expr[]
#     for (name, S) in zip(fieldnames(DT), DT.types)
#         if S == T
#             push!(assignments, :(a[$i] = dt.$name))
#             i += 1
#         end
#     end
#     # return assignments
#     quote $(assignments...) end
# end

# https://discourse.julialang.org/t/how-to-write-a-fast-loop-through-structure-fields/22535
@generated function struct2array!(a::AbstractArray{T}, dt::DT, i::Int) where {T, DT}
    assignments = Expr[]
    for (name, S) in zip(fieldnames(DT), DT.types)
        if S == T
            push!(assignments, :(a[i] = dt.$name))
            push!(assignments, :(i += 1))
        end
    end
    quote $(assignments...) end
end

function structs2array!(a::AbstractArray{T}, structs, i::Int) where {T}
    for dt in structs
      i = struct2array!(a, dt, i)
    end
    return i
end

@generated function array2struct!(dt::DT, a::AbstractArray{T}, i::Int) where {T, DT}
    assignments = Expr[]
    for (name, S) in zip(fieldnames(DT), DT.types)
        if S == T
            push!(assignments, :(dt.$name = a[i]))
            push!(assignments, :(i += 1))
        end
    end
    quote $(assignments...) end
end

function array2structs!(structs, a::AbstractArray{T}, i::Int) where {T}
    for dt in structs
      i = array2struct!(dt, a, i)
    end
    return i
end

function nfieldsoftype(T::DataType, dt::DT) where {DT}
    count(S -> S==T, DT.types)
end
    


x = zeros(10)
f = Foo(1.0, 8, 2.0)
g = Foo(2.0, 7, 3.0)
i = 1
i = struct2array!(x, f, i)
i = struct2array!(x, f, i)
i = struct2array!(x, g, i)
i = struct2array!(x, f, i)
i = struct2array!(x, g, i)
# struct2array!(x, g, i)
# @show i
@show x
i = 1
i = structs2array!(x, [f, g, f, f, f], i)
@show x

f.a = -5.0
f.c = -6.0
@show f
i = 1
i = array2struct!(f, x, i)
@show f

f = Foo(1.0, 1, 2.0)
g = Foo(2.0, 2, 3.0)
h = Foo(3.0, 3, 4.0)
x = collect(Float64, -20:20)
i = array2structs!([f, g, h], x, 1)
@show i, f, g, h

@show nfieldsoftype(Float64, f)
@show nfieldsoftype(Int64, g)
