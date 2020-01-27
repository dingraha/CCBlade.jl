mutable struct Foo{T}
    a::T
    b::Int64
    c::T
end

mutable struct Bar{T}
    d::T
    e::T
    f::Int64
    g::T
end

function to_array!(a, type, structs)
    i = 0
    for f in structs
        for name in fieldnames(typeof(f))
            val = getfield(f, name)
            if typeof(val) == type
                @show name, val
                i += 1
                a[i] = val
            end
        end
    end
    return nothing
end

function to_struct!(structs, type, a)
    i = 0
    for f in structs
        for name in fieldnames(typeof(f))
            val = getfield(f, name)
            if typeof(val) == type
                @show name, val
                i += 1
                setfield!(f, name, a[i])
            end
        end
    end
    return nothing
end

function num_fields(structs, type)
    i = 0
    for f in structs
        for name in fieldnames(typeof(f))
            val = getfield(f, name)
            if typeof(val) == type
                @show name, val
                i += 1
            end
        end
    end
    return i
end

f = Foo{Float64}(1, 2, 3)
g = Foo{Float64}(4, 5, 6)
h = Bar{Float64}(7, 8, 9, 10)

test = Vector{Float64}(undef, 10)
@show to_array!(test, Float64, (f, g, h))
@show test
test[1] = -5.0
test[2] = 27.0
test[3] = -4.0
test[4] = -9.0
to_struct!((f, g, h), Float64, test)
@show f, g, h

@show num_fields((f, g, h), Float64)

