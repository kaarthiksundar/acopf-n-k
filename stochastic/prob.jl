using PowerModels 

abstract AbstractNFForm <: PowerModels.AbstractDCPForm 

type StandardNFForm <: AbstractNFForm end
typealias NFPowerModel GenericPowerModel{StandardNFForm}

# default DC constructor
function NFPowerModel(data::Dict{AbstractString,Any}; kwargs...)
    return GenericPowerModel(data, StandardNFForm(); kwargs...)
end

function post_pfls{T}(pm::GenericPowerModel{T})

    PowerModels.variable_voltage(pm) # overloaded: phase angle variables for DC
    variable_generation(pm)
    variable_load_shed(pm) # TODO: add a PR to PowerModels; also overloaded
    if T != StandardNFForm 
        PowerModels.variable_line_flow(pm) 
    else
        variable_line_flow(pm)
    end 

    objective_min_load_shed(pm) # TODO: add PR to PowerModels

    PowerModels.constraint_theta_ref(pm) # overloaded: does nothing for SOC 
    PowerModels.constraint_voltage(pm) # overloaded: |W_ij|² ≦ Wᵢ⋅Wⱼ 

    for (i, bus) in pm.ref[:bus] # pm.ref[:bus] replaces pm.set
        constraint_kcl_ls(pm, bus)
    end

    for (i, branch) in pm.ref[:branch]
        constraint_ohms_from(pm, branch)
        constraint_ohms_to(pm, branch)

        PowerModels.constraint_phase_angle_difference(pm, branch)
        PowerModels.constraint_thermal_limit_from(pm, branch)
        PowerModels.constraint_thermal_limit_to(pm, branch)
    end
end

function variable_generation{T}(pm::GenericPowerModel{T}; kwargs...)
    variable_active_generation(pm; kwargs...)
    variable_reactive_generation(pm; kwargs...) # does nothing for DC
end

function variable_active_generation{T}(pm::GenericPowerModel{T}; bounded = true)
    if bounded
        @variable(pm.model, 0 <= pg[i in keys(pm.ref[:gen])] <= pm.ref[:gen][i]["pmax"], start = PowerModels.getstart(pm.ref[:gen], i, "pg_start"))
    else
        @variable(pm.model, pg[i in keys(pm.ref[:gen])], start = PowerModels.getstart(pm.ref[:gen], i, "pg_start"))
    end
    return pg
end

function variable_reactive_generation{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}; bounded = true)
    for i in keys(pm.ref[:gen])
        if (pm.ref[:gen][i]["qmin"] > 0 && pm.ref[:gen][i]["qmax"] > 0)
            pm.ref[:gen][i]["qmin"] = 0
        end
        if (pm.ref[:gen][i]["qmin"] < 0 && pm.ref[:gen][i]["qmax"] < 0)
            pm.ref[:gen][i]["qmax"] = 0
        end
    end
    if bounded
        @variable(pm.model, pm.ref[:gen][i]["qmin"] <= qg[i in keys(pm.ref[:gen])] <= pm.ref[:gen][i]["qmax"], start = PowerModels.getstart(pm.ref[:gen], i, "qg_start"))
    else
        @variable(pm.model, qg[i in keys(pm.ref[:gen])], start = PowerModels.getstart(pm.ref[:gen], i, "qg_start"))
    end
    return qg
end

function variable_reactive_generation{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T})
    # do nothing for dc model - no reactive variables
end

function variable_reactive_generation{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}; bounded = true)
    for i in keys(pm.ref[:gen])
        if (pm.ref[:gen][i]["qmin"] > 0 && pm.ref[:gen][i]["qmax"] > 0)
            pm.ref[:gen][i]["qmin"] = 0
        end
        if (pm.ref[:gen][i]["qmin"] < 0 && pm.ref[:gen][i]["qmax"] < 0)
            pm.ref[:gen][i]["qmax"] = 0
        end
    end
    if bounded
        @variable(pm.model, pm.ref[:gen][i]["qmin"] <= qg[i in keys(pm.ref[:gen])] <= pm.ref[:gen][i]["qmax"], start = PowerModels.getstart(pm.ref[:gen], i, "qg_start"))
    else
        @variable(pm.model, qg[i in keys(pm.ref[:gen])], start = PowerModels.getstart(pm.ref[:gen], i, "qg_start"))
    end
    return qg
end

function variable_load_shed{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T})
    ld_min = Dict(i => 0.0 for i in keys(pm.ref[:bus]))
    ld_max = Dict(i => 0.0 for i in keys(pm.ref[:bus]))
    for i in keys(pm.ref[:bus])
        if (pm.ref[:bus][i]["pd"] > 0)
            ld_max[i] = 1.0
        end
    end
    @variable(pm.model, ld_min[i] <= ld[i in keys(pm.ref[:bus])] <= ld_max[i], start = 0.0)
    return ld
end

function variable_load_shed{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T})
    ld_min = Dict(i => 0.0 for i in keys(pm.ref[:bus]))
    ld_max = Dict(i => 0.0 for i in keys(pm.ref[:bus]))
    for i in keys(pm.ref[:bus])
        if (pm.ref[:bus][i]["pd"] > 0 || pm.ref[:bus][i]["qd"] != 0)
            ld_max[i] = 1.0
        end
    end
    @variable(pm.model, ld_min[i] <= ld[i in keys(pm.ref[:bus])] <= ld_max[i], start = 0.0)
    return ld
end

function variable_load_shed{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T})
    ld_min = Dict(i => 0.0 for i in keys(pm.ref[:bus]))
    ld_max = Dict(i => 0.0 for i in keys(pm.ref[:bus]))
    for i in keys(pm.ref[:bus])
        if (pm.ref[:bus][i]["pd"] > 0 || pm.ref[:bus][i]["qd"] != 0)
            ld_max[i] = 1.0
        end
    end
    @variable(pm.model, ld_min[i] <= ld[i in keys(pm.ref[:bus])] <= ld_max[i], start = 0.0)
    return ld
end

function variable_line_flow{T <: AbstractNFForm}(pm::GenericPowerModel{T}; bounded = true)
    if bounded
        @variable(pm.model, -pm.ref[:branch][l]["rate_a"] <= p[(l,i,j) in pm.ref[:arcs_from]] <= pm.ref[:branch][l]["rate_a"], start = PowerModels.getstart(pm.ref[:branch], l, "p_start"))
    else
        @variable(pm.model, p[(l,i,j) in pm.ref[:arcs_from]], start = PowerModels.getstart(pm.ref[:branch], l, "p_start"))
    end

    p_expr = Dict([((l,i,j), 1.0*p[(l,i,j)]) for (l,i,j) in pm.ref[:arcs_from]])
    p_expr = merge(p_expr, Dict([((l,j,i), -1.0*p[(l,i,j)]) for (l,i,j) in pm.ref[:arcs_from]]))

    pm.model.ext[:p_expr] = p_expr
end 

# objective definition
function objective_min_load_shed{T}(pm::GenericPowerModel{T})
    c_pd = Dict(bp => 1 for bp in keys(pm.ref[:bus]))
    for (i, bus) in pm.ref[:bus]
        if (bus["pd"] < 0)
            c_pd[i] = 0
        end
    end
    ld = getvariable(pm.model, :ld)
    @objective(pm.model, Min, sum(pm.ref[:bus][i]["pd"] * c_pd[i] * ld[i] for i in keys(pm.ref[:bus])))
end

# constraint templates 
function constraint_kcl_ls{T}(pm::GenericPowerModel{T}, bus)
    i = bus["index"]
    bus_arcs = pm.ref[:bus_arcs][i]
    bus_gens = pm.ref[:bus_gens][i]
    
    return constraint_kcl_ls(pm, i, bus_arcs, bus_gens, bus["pd"], bus["qd"])
end 

function constraint_ohms_from{T}(pm::GenericPowerModel{T}, branch)
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = PowerModels.calc_branch_y(branch)
    return constraint_ohms_from(pm, f_bus, t_bus, f_idx, t_idx, g, b)
end 

function constraint_ohms_to{T}(pm::GenericPowerModel{T}, branch)
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = PowerModels.calc_branch_y(branch)
    return constraint_ohms_to(pm, f_bus, t_bus, f_idx, t_idx, g, b)
end 

# overloaded constraint functions
function constraint_kcl_ls{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, i, bus_arcs, bus_gens, pd, qd)
    pg = getvariable(pm.model, :pg)
    p_expr = pm.model.ext[:p_expr]
    ld = getvariable(pm.model, :ld)

    c = @constraint(pm.model, sum(p_expr[a] for a in bus_arcs) == sum(pg[g] for g in bus_gens) - pd*(1-ld[i]))
    # omit reactive constraint
    return Set([c])
end

function constraint_kcl_ls{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, i, bus_arcs, bus_gens, pd, qd)
    w = getvariable(pm.model, :w)[i]
    p = getvariable(pm.model, :p)
    q = getvariable(pm.model, :q)
    pg = getvariable(pm.model, :pg)
    qg = getvariable(pm.model, :qg)
    ld = getvariable(pm.model, :ld)

    c1 = @constraint(pm.model, sum(p[a] for a in bus_arcs) == sum(pg[g] for g in bus_gens) - pd*(1-ld[i]))
    c2 = @constraint(pm.model, sum(q[a] for a in bus_arcs) == sum(qg[g] for g in bus_gens) - qd*(1-ld[i]))
    return Set([c1, c2])
end

function constraint_kcl_ls{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, i, bus_arcs, bus_gens, pd, qd)
    v = getvariable(pm.model, :v)[i]
    p = getvariable(pm.model, :p)
    q = getvariable(pm.model, :q)
    pg = getvariable(pm.model, :pg)
    qg = getvariable(pm.model, :qg)
    ld = getvariable(pm.model, :ld)

    c1 = @constraint(pm.model, sum(p[a] for a in bus_arcs) == sum(pg[g] for g in bus_gens) - pd*(1-ld[i]))
    c2 = @constraint(pm.model, sum(q[a] for a in bus_arcs) == sum(qg[g] for g in bus_gens) - qd*(1-ld[i]))
    return Set([c1, c2])
end

function constraint_ohms_from{T <: AbstractNFForm}(pm::GenericPowerModel{T}, f_bus, t_bus, f_idx, t_idx, g, b)
     # Do nothing, this model is symmetric
     return Set()
end

function constraint_ohms_from{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, f_bus, t_bus, f_idx, t_idx, g, b)
    p_fr = getvariable(pm.model, :p)[f_idx]
    t_fr = getvariable(pm.model, :t)[f_bus]
    t_to = getvariable(pm.model, :t)[t_bus]

    c = @constraint(pm.model, p_fr == -b*(t_fr - t_to))
    return Set([c])
end

function constraint_ohms_to{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, f_bus, t_bus, f_idx, t_idx, g, b)
     # Do nothing, this model is symmetric
     return Set()
end

function constraint_ohms_from{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, f_bus, t_bus, f_idx, t_idx, g, b)
    p_fr = getvariable(pm.model, :p)[f_idx]
    q_fr = getvariable(pm.model, :q)[f_idx]
    w_fr = getvariable(pm.model, :w)[f_bus]
    w_to = getvariable(pm.model, :w)[t_bus]
    wr = getvariable(pm.model, :wr)[(f_bus, t_bus)]
    wi = getvariable(pm.model, :wi)[(f_bus, t_bus)]

    c1 = @constraint(pm.model, p_fr == g*w_fr + (-g*wr) + (-b*wi) )
    c2 = @constraint(pm.model, q_fr == -b*w_fr - (-b*wr) + (-g*wi) )
    return Set([c1, c2])
end

function constraint_ohms_to{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, f_bus, t_bus, f_idx, t_idx, g, b)
    q_to = getvariable(pm.model, :q)[t_idx]
    p_to = getvariable(pm.model, :p)[t_idx]
    w_fr = getvariable(pm.model, :w)[f_bus]
    w_to = getvariable(pm.model, :w)[t_bus]
    wr = getvariable(pm.model, :wr)[(f_bus, t_bus)]
    wi = getvariable(pm.model, :wi)[(f_bus, t_bus)]

    c1 = @constraint(pm.model, p_to == g*w_to + (-g*wr) + (b*wi) )
    c2 = @constraint(pm.model, q_to == -b*w_to - (-b*wr) + (g*wi) )
    return Set([c1, c2])
end

function constraint_ohms_from{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, f_bus, t_bus, f_idx, t_idx, g, b)
    p_fr = getvariable(pm.model, :p)[f_idx]
    q_fr = getvariable(pm.model, :q)[f_idx]
    v_fr = getvariable(pm.model, :v)[f_bus]
    v_to = getvariable(pm.model, :v)[t_bus]
    t_fr = getvariable(pm.model, :t)[f_bus]
    t_to = getvariable(pm.model, :t)[t_bus]

    c1 = @NLconstraint(pm.model, p_fr == g*v_fr^2 + -g*v_fr*v_to*cos(t_fr-t_to) + -b*v_fr*v_to*sin(t_fr-t_to) )
    c2 = @NLconstraint(pm.model, q_fr == -b*v_fr^2 + b*v_fr*v_to*cos(t_fr-t_to) + -g*v_fr*v_to*sin(t_fr-t_to) )
    return Set([c1, c2])
end

function constraint_ohms_to{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, f_bus, t_bus, f_idx, t_idx, g, b)
    p_to = getvariable(pm.model, :p)[t_idx]
    q_to = getvariable(pm.model, :q)[t_idx]
    v_fr = getvariable(pm.model, :v)[f_bus]
    v_to = getvariable(pm.model, :v)[t_bus]
    t_fr = getvariable(pm.model, :t)[f_bus]
    t_to = getvariable(pm.model, :t)[t_bus]

    c1 = @NLconstraint(pm.model, p_to == g*v_to^2 + -g*v_fr*v_to*cos(t_to-t_fr) + -b*v_fr*v_to*sin(t_to-t_fr) )
    c2 = @NLconstraint(pm.model, q_to == -b*v_to^2 + b*v_fr*v_to*cos(t_to-t_fr) + -g*v_fr*v_to*sin(t_to-t_fr) )
    return Set([c1, c2])
end
