using PowerModels

function post_pfls{T}(pm::GenericPowerModel{T})

    PowerModels.variable_complex_voltage(pm) # overloaded: phase angle variables for DC
    variable_active_generation(pm)
    variable_reactive_generation(pm) # does nothing for DC
    variable_load_shed(pm) # TODO: add a PR to PowerModels; also overloaded
    PowerModels.variable_active_line_flow(pm) # overloaded: p(i,j) = -p(j,i)
    PowerModels.variable_reactive_line_flow(pm) # overloaded: does nothing for DC

    objective_min_load_shed(pm) # TODO: add PR to PowerModels

    PowerModels.constraint_theta_ref(pm) # overloaded: does nothing for SOC -
    PowerModels.constraint_complex_voltage(pm) # overloaded: |W_ij|² ≦ Wᵢ⋅Wⱼ - does not return reference

    for (i, bus) in pm.set.buses
        constraint_active_kcl_ls(pm, bus)
        constraint_reactive_kcl_ls(pm, bus)
    end

    for (i, branch) in pm.set.branches
        constraint_active_ohms(pm, branch)
        constraint_reactive_ohms(pm, branch)

        PowerModels.constraint_phase_angle_difference(pm, branch)
        PowerModels.constraint_thermal_limit_from(pm, branch)
        PowerModels.constraint_thermal_limit_to(pm, branch)
    end

end

function variable_active_generation{T}(pm::GenericPowerModel{T}; bounded = true)
    if bounded
        @variable(pm.model, 0 <= pg[i in pm.set.gen_indexes] <= pm.set.gens[i]["pmax"], start = PowerModels.getstart(pm.set.gens, i, "pg_start"))
    else
        @variable(pm.model, pg[i in pm.set.gen_indexes], start = PowerModels.getstart(pm.set.gens, i, "pg_start"))
    end
    return pg
end

function variable_reactive_generation{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}; bounded = true)
    for i in pm.set.gen_indexes
        if (pm.set.gens[i]["qmin"] > 0 && pm.set.gens[i]["qmax"] > 0)
            pm.set.gens[i]["qmin"] = 0
        end
        if (pm.set.gens[i]["qmin"] < 0 && pm.set.gens[i]["qmax"] < 0)
            pm.set.gens[i]["qmax"] = 0
        end
    end
    if bounded
        @variable(pm.model, pm.set.gens[i]["qmin"] <= qg[i in pm.set.gen_indexes] <= pm.set.gens[i]["qmax"], start = PowerModels.getstart(pm.set.gens, i, "qg_start"))
    else
        @variable(pm.model, qg[i in pm.set.gen_indexes], start = PowerModel.getstart(pm.set.gens, i, "qg_start"))
    end
    return qg
end

function variable_reactive_generation{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T})
    # do nothing for dc model - no reactive variables
end

function variable_reactive_generation{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}; bounded = true)
    for i in pm.set.gen_indexes
        if (pm.set.gens[i]["qmin"] > 0 && pm.set.gens[i]["qmax"] > 0)
            pm.set.gens[i]["qmin"] = 0
        end
        if (pm.set.gens[i]["qmin"] < 0 && pm.set.gens[i]["qmax"] < 0)
            pm.set.gens[i]["qmax"] = 0
        end
    end
    if bounded
        @variable(pm.model, pm.set.gens[i]["qmin"] <= qg[i in pm.set.gen_indexes] <= pm.set.gens[i]["qmax"], start = PowerModels.getstart(pm.set.gens, i, "qg_start"))
    else
        @variable(pm.model, qg[i in pm.set.gen_indexes], start = PowerModel.getstart(pm.set.gens, i, "qg_start"))
    end
    return qg
end

function variable_load_shed{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T})
    ld_min = [i => 0.0 for i in pm.set.bus_indexes]
    ld_max = [i => 0.0 for i in pm.set.bus_indexes]
    for i in pm.set.bus_indexes
        if (pm.set.buses[i]["pd"] > 0)
            ld_max[i] = 1.0
        end
    end
    @variable(pm.model, ld_min[i] <= ld[i in pm.set.bus_indexes] <= ld_max[i], start = 0.0)
    return ld
end

function variable_load_shed{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T})
    ld_min = [i => 0.0 for i in pm.set.bus_indexes]
    ld_max = [i => 0.0 for i in pm.set.bus_indexes]
    for i in pm.set.bus_indexes
        if (pm.set.buses[i]["pd"] > 0 || pm.set.buses[i]["qd"] != 0)
            ld_max[i] = 1.0
        end
    end
    @variable(pm.model, ld_min[i] <= ld[i in pm.set.bus_indexes] <= ld_max[i], start = 0.0)
    return ld
end

function variable_load_shed{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T})
    ld_min = [i => 0.0 for i in pm.set.bus_indexes]
    ld_max = [i => 0.0 for i in pm.set.bus_indexes]
    for i in pm.set.bus_indexes
        if (pm.set.buses[i]["pd"] > 0 || pm.set.buses[i]["qd"] != 0)
            ld_max[i] = 1.0
        end
    end
    @variable(pm.model, ld_min[i] <= ld[i in pm.set.bus_indexes] <= ld_max[i], start = 0.0)
    return ld
end

function objective_min_load_shed{T}(pm::GenericPowerModel{T})
    c_pd = [bp => 1 for bp in pm.set.bus_indexes]
    for (i, bus) in pm.set.buses
        if (bus["pd"] < 0)
            c_pd[i] = 0
        end
    end
    ld = getvariable(pm.model, :ld)
    @objective(pm.model, Min, sum{pm.set.buses[i]["pd"] * c_pd[i] * ld[i], i=pm.set.bus_indexes} )
end

function constraint_active_kcl_ls{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, bus)
    i = bus["index"]
    bus_branches = pm.set.bus_branches[i]
    bus_gens = pm.set.bus_gens[i]

    pg = getvariable(pm.model, :pg)
    p_expr = pm.model.ext[:p_expr]
    ld = getvariable(pm.model, :ld)

    c = @constraint(pm.model, sum{p_expr[a], a in bus_branches} == sum{pg[g], g in bus_gens} - bus["pd"]*(1-ld[i]))
    return Set([c])
end

function constraint_reactive_kcl_ls{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, bus)
    # do nothing
    return Set()
end

function constraint_active_kcl_ls{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, bus)
    i = bus["index"]
    bus_branches = pm.set.bus_branches[i]
    bus_gens = pm.set.bus_gens[i]

    w = getvariable(pm.model, :w)
    p = getvariable(pm.model, :p)
    pg = getvariable(pm.model, :pg)
    ld = getvariable(pm.model, :ld)

    c = @constraint(pm.model, sum{p[a], a in bus_branches} == sum{pg[g], g in bus_gens} - bus["pd"]*(1-ld[i]))
    return Set([c])
end

function constraint_reactive_kcl_ls{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, bus)
    i = bus["index"]
    bus_branches = pm.set.bus_branches[i]
    bus_gens = pm.set.bus_gens[i]

    w = getvariable(pm.model, :w)
    q = getvariable(pm.model, :q)
    qg = getvariable(pm.model, :qg)
    ld = getvariable(pm.model, :ld)

    c = @constraint(pm.model, sum{q[a], a in bus_branches} == sum{qg[g], g in bus_gens} - bus["qd"]*(1-ld[i]))
    return Set([c])
end

function constraint_active_kcl_ls{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, bus)
    i = bus["index"]
    bus_branches = pm.set.bus_branches[i]
    bus_gens = pm.set.bus_gens[i]

    p = getvariable(pm.model, :p)
    pg = getvariable(pm.model, :pg)
    ld = getvariable(pm.model, :ld)

    c = @constraint(pm.model, sum{p[a], a in bus_branches} == sum{pg[g], g in bus_gens} - bus["pd"]*(1-ld[i]))
    return Set([c])
end

function constraint_reactive_kcl_ls{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, bus)
    i = bus["index"]
    bus_branches = pm.set.bus_branches[i]
    bus_gens = pm.set.bus_gens[i]

    q = getvariable(pm.model, :q)
    qg = getvariable(pm.model, :qg)
    ld = getvariable(pm.model, :ld)

    c = @constraint(pm.model, sum{q[a], a in bus_branches} == sum{qg[g], g in bus_gens} - bus["qd"]*(1-ld[i]))
    return Set([c])
end

function constraint_active_ohms{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, branch)
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    p_fr = getvariable(pm.model, :p)[f_idx]
    t_fr = getvariable(pm.model, :t)[f_bus]
    t_to = getvariable(pm.model, :t)[t_bus]

    b = branch["b"]

    c = @constraint(pm.model, p_fr == -b*(t_fr - t_to))
    return Set([c])
end

function constraint_reactive_ohms{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, branch)
    # do nothing
    return Set()
end

function constraint_active_ohms{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, branch)
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    p_fr = getvariable(pm.model, :p)[f_idx]
    p_to = getvariable(pm.model, :p)[t_idx]
    w_fr = getvariable(pm.model, :w)[f_bus]
    w_to = getvariable(pm.model, :w)[t_bus]
    wr = getvariable(pm.model, :wr)[(f_bus, t_bus)]
    wi = getvariable(pm.model, :wi)[(f_bus, t_bus)]

    g = branch["g"]
    b = branch["b"]

    c1 = @constraint(pm.model, p_fr == g*w_fr + (-g*wr) + (-b*wi) )
    c2 = @constraint(pm.model, p_to == g*w_to + (-g*wr) + (b*wi) )
    return Set([c1, c2])
end

function constraint_reactive_ohms{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, branch)
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    q_fr = getvariable(pm.model, :q)[f_idx]
    q_to = getvariable(pm.model, :q)[t_idx]
    w_fr = getvariable(pm.model, :w)[f_bus]
    w_to = getvariable(pm.model, :w)[t_bus]
    wr = getvariable(pm.model, :wr)[(f_bus, t_bus)]
    wi = getvariable(pm.model, :wi)[(f_bus, t_bus)]

    g = branch["g"]
    b = branch["b"]

    c1 = @constraint(pm.model, q_fr == -b*w_fr - (-b*wr) + (-g*wi) )
    c2 = @constraint(pm.model, q_to == -b*w_to - (-b*wr) + (g*wi) )
    return Set([c1, c2])
end

function constraint_active_ohms{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, branch)
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    p_fr = getvariable(pm.model, :p)[f_idx]
    p_to = getvariable(pm.model, :p)[t_idx]
    v_fr = getvariable(pm.model, :v)[f_bus]
    v_to = getvariable(pm.model, :v)[t_bus]
    t_fr = getvariable(pm.model, :t)[f_bus]
    t_to = getvariable(pm.model, :t)[t_bus]


    g = branch["g"]
    b = branch["b"]

    c1 = @NLconstraint(pm.model, p_fr == g*v_fr^2 + -g*v_fr*v_to*cos(t_fr-t_to) + -b*v_fr*v_to*sin(t_fr-t_to) )
    c2 = @NLconstraint(pm.model, p_to == g*v_to^2 + -g*v_fr*v_to*cos(t_to-t_fr) + -b*v_fr*v_to*sin(t_to-t_fr) )
    return Set([c1, c2])
end

function constraint_reactive_ohms{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, branch)
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    q_fr = getvariable(pm.model, :q)[f_idx]
    q_to = getvariable(pm.model, :q)[t_idx]
    v_fr = getvariable(pm.model, :v)[f_bus]
    v_to = getvariable(pm.model, :v)[t_bus]
    t_fr = getvariable(pm.model, :t)[f_bus]
    t_to = getvariable(pm.model, :t)[t_bus]

    g = branch["g"]
    b = branch["b"]

    c1 = @NLconstraint(pm.model, q_fr == -b*v_fr^2 + b*v_fr*v_to*cos(t_fr-t_to) + -g*v_fr*v_to*sin(t_fr-t_to) )
    c2 = @NLconstraint(pm.model, q_to == -b*v_to^2 + b*v_fr*v_to*cos(t_to-t_fr) + -g*v_fr*v_to*sin(t_to-t_fr) )
    return Set([c1, c2])
end

