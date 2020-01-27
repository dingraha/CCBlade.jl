import ForwardDiff

using CCBlade: residual, Outputs, Rotor, Section, OperatingPoint
using OpenMDAO: structs2array!, array2structs!

struct PartialsWrt{TF}
    phi::TF

    r::TF
    chord::TF
    theta::TF

    Vx::TF
    Vy::TF
    rho::TF
    mu::TF
    asound::TF

    Rhub::TF
    Rtip::TF
    pitch::TF
    precone::TF

end

# Need this for the mapslices call in output_partials.
PartialsWrt(x::AbstractArray) = PartialsWrt(x...)

# Convenience function to access fields within an array of structs, from Andrew
# Ning.
Base.getproperty(obj::Array{PartialsWrt{TF}, N}, sym::Symbol) where {TF, N} = getfield.(obj, sym)

function pack_inputs(phi, rotor, section, op)
    r = section.r
    chord = section.chord
    theta = section.theta
    Rhub = rotor.Rhub
    Rtip = rotor.Rtip
    pitch = rotor.pitch
    precone = rotor.precone
    Vx = op.Vx
    Vy = op.Vy
    rho = op.rho
    mu = op.mu
    asound = op.asound
    x = [phi, r, chord, theta, Vx, Vy, rho, mu, asound, Rhub, Rtip, pitch, precone]

    return x
end

function unpack_inputs(x, af, B, turbine)
    phi = x[1]
    r = x[2]
    chord = x[3]
    theta = x[4]
    Vx, Vy, rho, mu, asound = x[5], x[6], x[7], x[8], x[9]
    Rhub, Rtip, pitch, precone = x[10], x[11], x[12], x[13]
    rotor = Rotor(Rhub, Rtip, B, turbine, pitch, precone)
    section = Section(r, chord, theta, af)
    op = OperatingPoint(Vx, Vy, rho, mu, asound)
    return phi, rotor, section, op
end

function residual_partials(phi, rotor, section, op)
    af = section.af
    B = rotor.B
    turbine = rotor.turbine

    # Get a version of the residual function that's compatible with ForwardDiff.
    function R(inputs)
        _phi, _rotor, _section, _op = unpack_inputs(inputs, af, B, turbine)
        res, out = residual(_phi, _rotor, _section, _op)
        return res
    end

    # Do it.
    x = pack_inputs(phi, rotor, section, op)
    return PartialsWrt(ForwardDiff.gradient(R, x))

end

function residual_partials_v2(phi, rotor, section, op, x::AbstractArray{T}) where {T}
    af = section.af
    B = rotor.B
    turbine = rotor.turbine

    # Get a version of the residual function that's compatible with ForwardDiff.
    function R(inputs)

        # Create empty structs.
        _rotor = Rotor{T}(B, turbine)
        _section = Section{T}(af)
        _op = OperatingPoint{T}()

        # Set the struct components with the `inputs` array.
        _phi = inputs[1]
        array2structs!([_rotor, _section, _op], inputs, 2)

        # Get the residual.
        res, out = residual(_phi, _rotor, _section, _op)

        return res
    end

    # Create the input array for the `R` function.
    x[1] = phi
    structs2array!(x, [rotor, section, op], 2)

    # Get the derivative of R. This will return an array with length equal to
    # the number of elements in x.
    deriv = ForwardDiff.gradient(R, x)

    # Create new empyt structs that will hold the derivative of R.
    drotor = Rotor{T}(B, turbine)
    dsection = Section{T}(af)
    dop = OperatingPoint{T, T}()

    # Put the derivative into the new structs.
    dphi = deriv[1]
    array2structs!([drotor, dsection, dop], deriv, 2)

    return dphi, drotor, dsection, dop

end

function output_partials(phi, rotor, section, op)
    af = section.af
    B = rotor.B
    turbine = rotor.turbine

    # Get a version of the output function that's compatible with ForwardDiff.
    function R(inputs)
        _phi, _rotor, _section, _op = unpack_inputs(inputs, af, B, turbine)
        res, out = residual(_phi, _rotor, _section, _op)
        return [getfield(out, i) for i in fieldnames(typeof(out))]
    end

    # Do it.
    x = pack_inputs(phi, rotor, section, op)
    return Outputs(mapslices(PartialsWrt, ForwardDiff.jacobian(R, x), dims=2)...)
end
