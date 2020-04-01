import Base.convert
using OpenMDAO
import OpenMDAO: detect_apply_nonlinear, detect_guess_nonlinear, detect_apply_linear
using CCBlade: solve

struct CCBladeResidualComp{TAF} <: OpenMDAO.AbstractImplicitComp
    num_nodes::Int
    num_radial::Int
    af::Vector{TAF}
    B::Int
    turbine::Bool
end

function CCBladeResidualComp(; num_nodes, num_radial, af, B, turbine)
    # Check if the airfoil interpolation passed is a num_radial-length array.
    try
        num_af = length(af)
        if num_af != num_radial
            throw(DomainError("af has length $num_af, but should have length $num_radial"))
        end
    catch e
        if isa(e, MethodError)
            # af is not an array of stuff, so assume it's just a single
            # function, and make it have shape (num_radial,).
            af = fill(af, num_radial)
        else
            # Some other error happened, so rethrow it.
            rethrow(e)
        end
    end

    TAF = eltype(af)
    return CCBladeResidualComp{TAF}(num_nodes, num_radial, af, B, turbine)
end

function OpenMDAO.setup(self::CCBladeResidualComp)
    num_nodes = self.num_nodes
    num_radial = self.num_radial

    input_data = [
        VarData("r", shape=(num_nodes, num_radial), val=1., units="m"),
        VarData("chord", shape=(num_nodes, num_radial), val=1., units="m"),
        VarData("theta", shape=(num_nodes, num_radial), val=1., units="rad"),
        VarData("Vx", shape=(num_nodes, num_radial), val=1., units="m/s"),
        VarData("Vy", shape=(num_nodes, num_radial), val=1., units="m/s"),
        VarData("rho", shape=(num_nodes, 1), val=1., units="kg/m**3"),
        VarData("mu", shape=(num_nodes, 1), val=1., units="N/m**2*s"),
        VarData("asound", shape=(num_nodes, 1), val=1., units="m/s"),
        VarData("Rhub", shape=(num_nodes, 1), val=1., units="m"),
        VarData("Rtip", shape=(num_nodes, 1), val=1., units="m"),
        VarData("pitch", shape=(num_nodes, 1), val=1., units="rad"),
        VarData("precone", shape=(num_nodes, 1), val=1., units="rad")]

    output_data = [
        VarData("phi", shape=(num_nodes, num_radial), val=1., units="rad"),
        VarData("Np", shape=(num_nodes, num_radial), val=1., units="N/m"),
        VarData("Tp", shape=(num_nodes, num_radial), val=1., units="N/m"),
        VarData("a", shape=(num_nodes, num_radial), val=1.),
        VarData("ap", shape=(num_nodes, num_radial), val=1.),
        VarData("u", shape=(num_nodes, num_radial), val=1., units="m/s"),
        VarData("v", shape=(num_nodes, num_radial), val=1., units="m/s"),
        VarData("W", shape=(num_nodes, num_radial), val=1., units="m/s"),
        VarData("cl", shape=(num_nodes, num_radial), val=1.),
        VarData("cd", shape=(num_nodes, num_radial), val=1.),
        VarData("cn", shape=(num_nodes, num_radial), val=1.),
        VarData("ct", shape=(num_nodes, num_radial), val=1.),
        VarData("F", shape=(num_nodes, num_radial), val=1.),
        VarData("G", shape=(num_nodes, num_radial), val=1.)]

    partials_data = Vector{PartialsData}()

    of_names = ["phi", "Np", "Tp", "a", "ap", "u", "v", "W", "cl", "cd", "cn", "ct", "F", "G"]

    ss_sizes = Dict(:i=>num_nodes, :j=>num_radial)
    rows, cols = get_rows_cols(ss_sizes=ss_sizes, of_ss=[:i, :j], wrt_ss=[:i])
    for name in of_names
        push!(partials_data, PartialsData(name, "Rhub", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "Rtip", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "pitch", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "precone", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "rho", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "mu", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "asound", rows=rows, cols=cols))
    end

    rows, cols = get_rows_cols(ss_sizes=ss_sizes, of_ss=[:i, :j], wrt_ss=[:i, :j])
    for name in of_names
        push!(partials_data, PartialsData(name, "r", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "chord", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "theta", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "Vx", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "Vy", rows=rows, cols=cols))
        push!(partials_data, PartialsData(name, "phi", rows=rows, cols=cols))
    end

    for name in ["Np", "Tp", "a", "ap", "u", "v", "W", "cl", "cd", "cn", "ct", "F", "G"]
        push!(partials_data, PartialsData(name, name, rows=rows, cols=cols, val=1.0))
    end

    return input_data, output_data, partials_data
end

function OpenMDAO.linearize!(self::CCBladeResidualComp, inputs, outputs, partials)
    num_nodes = self.num_nodes
    num_radial = self.num_radial
    af = self.af
    B = self.B
    turbine = self.turbine

    r = inputs["r"]
    chord = inputs["chord"]
    theta = inputs["theta"]
    Vx = inputs["Vx"]
    Vy = inputs["Vy"]
    rho = inputs["rho"]
    mu = inputs["mu"]
    asound = inputs["asound"]
    Rhub = inputs["Rhub"]
    Rtip = inputs["Rtip"]
    pitch = inputs["pitch"]
    precone = inputs["precone"]

    phi = outputs["phi"]

    for i in 1:num_nodes
        for j in 1:num_radial
            # Create the input structs.
            rotor = Rotor(Rhub[i, 1], Rtip[i, 1], B, turbine, pitch[i, 1], precone[i, 1])
            section = Section(r[i, j], chord[i, j], theta[i, j], af[j])
            op = OperatingPoint(Vx[i, j], Vy[i, j], rho[i, 1], mu[i, 1], asound[i, 1])

            # Find the partials of the phi residual.
            residual_deriv = residual_partials(phi[i, j], rotor, section, op)

            # Store the derivatives of the phi residual wrt phi.
            str = "phi"
            sym = Symbol(str)
            # reshape does not copy data: https://github.com/JuliaLang/julia/issues/112
            deriv = transpose(reshape(partials["phi", str], (num_radial, num_nodes)))
            deriv[i, j] = getfield(residual_deriv, sym)

            # Store the derivatives of the phi residual wrt the inputs.
            for str in keys(inputs)
                sym = Symbol(str)
                deriv = transpose(reshape(partials["phi", str], (num_radial, num_nodes)))
                deriv[i, j] = getfield(residual_deriv, sym)
            end

            # Get the derivatives of the explicit outputs.
            output_derivs = output_partials(phi[i, j], rotor, section, op)

            # Copy the derivatives of the explicit outputs into the partials dict.
            for of_str in keys(outputs)
                if of_str == "phi"
                    continue
                else
                    of_sym = Symbol(of_str)
                    for wrt_str in keys(inputs)
                        wrt_sym = Symbol(wrt_str)
                        # reshape does not copy data: https://github.com/JuliaLang/julia/issues/112
                        deriv = transpose(reshape(partials[of_str, wrt_str], (num_radial, num_nodes)))
                        deriv[i, j] = -getfield(getfield(output_derivs, of_sym), wrt_sym)
                    end
                    # Also need the derivative of each output with respect to phi, but
                    # phi is an output, not an input, so we'll need to handle that
                    # seperately.
                    wrt_str = "phi"
                    wrt_sym = Symbol(wrt_str)
                    # reshape does not copy data: https://github.com/JuliaLang/julia/issues/112
                    deriv = transpose(reshape(partials[of_str, wrt_str], (num_radial, num_nodes)))
                    deriv[i, j] = -getfield(getfield(output_derivs, of_sym), wrt_sym)
                end
            end
        end
    end

    return nothing
end

function OpenMDAO.solve_nonlinear!(self::CCBladeResidualComp, inputs, outputs)
    num_nodes = self.num_nodes
    num_radial = self.num_radial
    af = self.af
    B = self.B
    turbine = self.turbine

    r = inputs["r"]
    chord = inputs["chord"]
    theta = inputs["theta"]
    Vx = inputs["Vx"]
    Vy = inputs["Vy"]
    rho = inputs["rho"]
    mu = inputs["mu"]
    asound = inputs["asound"]
    Rhub = inputs["Rhub"]
    Rtip = inputs["Rtip"]
    pitch = inputs["pitch"]
    precone = inputs["precone"]

    for i in 1:num_nodes
        for j in 1:num_radial
            # Create the input structs.
            rotor = Rotor(Rhub[i, 1], Rtip[i, 1], B, turbine, pitch[i, 1], precone[i, 1])
            section = Section(r[i, j], chord[i, j], theta[i, j], af[j])
            op = OperatingPoint(Vx[i, j], Vy[i, j], rho[i, 1], mu[i, 1], asound[i, 1])

            # Solve the BEMT equation.
            out = solve(rotor, section, op)

            # Save the outputs.
            for str in keys(outputs)
                sym = Symbol(str)
                outputs[str][i, j] = getfield(out, sym)
            end
        end
    end

    return nothing
end

detect_apply_nonlinear(::Type{<:CCBladeResidualComp}) = false
detect_guess_nonlinear(::Type{<:CCBladeResidualComp}) = false
detect_apply_linear(::Type{<:CCBladeResidualComp}) = false
