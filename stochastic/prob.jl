using PowerModels 

using Memento
setlevel!(getlogger(PowerModels), "error")

abstract type AbstractNFForm<:PowerModels.AbstractDCPForm end

type StandardNFForm <: AbstractNFForm end
const NFPowerModel = GenericPowerModel{StandardNFForm}

# default DC constructor
function NFPowerModel(data::Dict{AbstractString,Any}; kwargs...)
    return GenericPowerModel(data, StandardNFForm(); kwargs...)
end

function post_pfls{T}(pm::GenericPowerModel{T})

    PowerModels.variable_voltage(pm) # overloaded: phase angle variables for DC
    variable_generation(pm)
    variable_load_shed(pm) # TODO: add a PR to PowerModels; also overloaded
    if T != StandardNFForm 
        PowerModels.variable_branch_flow(pm) 
    else
        variable_branch_flow(pm)
    end 
    PowerModels.variable_dcline_flow(pm)

    objective_min_load_shed(pm) # TODO: add PR to PowerModels

    PowerModels.constraint_theta_ref(pm) # overloaded: does nothing for SOC 
    PowerModels.constraint_voltage(pm) # overloaded: |W_ij|² ≦ Wᵢ⋅Wⱼ 

    for (i, bus) in pm.ref[:nw][0][:bus] # pm.ref[:nw][0][:bus] replaces pm.set
        constraint_kcl_ls(pm, bus)
    end

    for (i, branch) in pm.ref[:nw][0][:branch]
        constraint_ohms_from(pm, branch)
        constraint_ohms_to(pm, branch)

        PowerModels.constraint_phase_angle_difference(pm, branch)
        PowerModels.constraint_thermal_limit_from(pm, branch)
        PowerModels.constraint_thermal_limit_to(pm, branch)
    end
    
    for i in PowerModels.ids(pm, :dcline)
        PowerModels.constraint_dcline(pm, i)
    end

end

function variable_generation{T}(pm::GenericPowerModel{T}, n::Int=pm.cnw; kwargs...)
    variable_active_generation(pm, n; kwargs...)
    variable_reactive_generation(pm, n; kwargs...) # does nothing for DC
end

function variable_active_generation{T}(pm::GenericPowerModel{T}, n::Int=pm.cnw; bounded = true)
    if bounded
        pm.var[:nw][n][:pg] = @variable(pm.model,
                                        [i in keys(pm.ref[:nw][n][:gen])], basename="$(n)_pg",
                                        lowerbound = 0,
                                        upperbound = pm.ref[:nw][n][:gen][i]["pmax"],
                                        start = getstart(pm.ref[:nw][n][:gen], i, "pg_start")
                                       )
    else
        pm.var[:nw][n][:pg] = @variable(pm.model,
                                        [i in keys(pm.ref[:nw][n][:gen])], basename="$(n)_pg",
                                        start = getstart(pm.ref[:nw][n][:gen], i, "pg_start")
                                       )
    end
end

function variable_reactive_generation{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, n::Int=pm.cnw; bounded = true)
    for i in keys(pm.ref[:nw][n][:gen])
        if (pm.ref[:nw][n][:gen][i]["qmin"] > 0 && pm.ref[:nw][n][:gen][i]["qmax"] > 0)
            pm.ref[:nw][n][:gen][i]["qmin"] = 0
        end
        if (pm.ref[:nw][n][:gen][i]["qmin"] < 0 && pm.ref[:nw][n][:gen][i]["qmax"] < 0)
            pm.ref[:nw][n][:gen][i]["qmax"] = 0
        end
    end
    if bounded
        pm.var[:nw][n][:qg] = @variable(pm.model,
                                        [i in keys(pm.ref[:nw][n][:gen])], basename="$(n)_qg",
                                        lowerbound = pm.ref[:nw][n][:gen][i]["qmin"],
                                        upperbound = pm.ref[:nw][n][:gen][i]["qmax"],
                                        start = getstart(pm.ref[:nw][n][:gen], i, "qg_start")
                                       )
    else
        pm.var[:nw][n][:qg] = @variable(pm.model,
                                        [i in keys(pm.ref[:nw][n][:gen])], basename="$(n)_qg",
                                        start = getstart(pm.ref[:nw][n][:gen], i, "qg_start")
                                       )
    end

end

function variable_reactive_generation{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, n::Int=pm.cnw)
    # do nothing for dc model - no reactive variables
end

function variable_reactive_generation{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, n::Int=pm.cnw; bounded = true)
    for i in keys(pm.ref[:nw][n][:gen])
        if (pm.ref[:nw][n][:gen][i]["qmin"] > 0 && pm.ref[:nw][n][:gen][i]["qmax"] > 0)
            pm.ref[:nw][n][:gen][i]["qmin"] = 0
        end
        if (pm.ref[:nw][n][:gen][i]["qmin"] < 0 && pm.ref[:nw][n][:gen][i]["qmax"] < 0)
            pm.ref[:nw][n][:gen][i]["qmax"] = 0
        end
    end
    if bounded
        pm.var[:nw][n][:qg] = @variable(pm.model,
                                        [i in keys(pm.ref[:nw][n][:gen])], basename="$(n)_qg",
                                        lowerbound = pm.ref[:nw][n][:gen][i]["qmin"],
                                        upperbound = pm.ref[:nw][n][:gen][i]["qmax"],
                                        start = getstart(pm.ref[:nw][n][:gen], i, "qg_start")
                                       )
    else
        pm.var[:nw][n][:qg] = @variable(pm.model,
                                        [i in keys(pm.ref[:nw][n][:gen])], basename="$(n)_qg",
                                        start = getstart(pm.ref[:nw][n][:gen], i, "qg_start")
                                       )
    end
end

function variable_load_shed{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, n::Int=pm.cnw)
    ld_min = Dict(i => 0.0 for i in keys(pm.ref[:nw][n][:load]))
    ld_max = Dict(i => 0.0 for i in keys(pm.ref[:nw][n][:load]))
    for i in keys(pm.ref[:nw][n][:load])
        if (pm.ref[:nw][n][:load][i]["pd"] > 0)
            ld_max[i] = 1.0
        end
    end
    pm.var[:nw][n][:ld] = @variable(pm.model, 
                                    [i in keys(pm.ref[:nw][n][:load])], basename="$(n)_ld",
                                    lowerbound = ld_min[i], upperbound = ld_max[i], start = 0.0)
end

function variable_load_shed{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, n::Int=pm.cnw)
    ld_min = Dict(i => 0.0 for i in keys(pm.ref[:nw][n][:load]))
    ld_max = Dict(i => 0.0 for i in keys(pm.ref[:nw][n][:load]))
    for i in keys(pm.ref[:nw][n][:load])
        if (pm.ref[:nw][n][:load][i]["pd"] > 0 || pm.ref[:nw][n][:load][i]["qd"] != 0)
            ld_max[i] = 1.0
        end
    end
    pm.var[:nw][n][:ld] = @variable(pm.model, 
                                    [i in keys(pm.ref[:nw][n][:load])], basename="$(n)_ld",
                                    lowerbound = ld_min[i], upperbound = ld_max[i], start = 0.0)
end

function variable_load_shed{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, n::Int=pm.cnw)
    ld_min = Dict(i => 0.0 for i in keys(pm.ref[:nw][n][:load]))
    ld_max = Dict(i => 0.0 for i in keys(pm.ref[:nw][n][:load]))
    for i in keys(pm.ref[:nw][n][:load])
        if (pm.ref[:nw][n][:load][i]["pd"] > 0 || pm.ref[:nw][n][:load][i]["qd"] != 0)
            ld_max[i] = 1.0
        end
    end
    pm.var[:nw][n][:ld] = @variable(pm.model, 
                                    [i in keys(pm.ref[:nw][n][:load])], basename="$(n)_ld",
                                    lowerbound = ld_min[i], upperbound = ld_max[i], start = 0.0)
end

function variable_branch_flow{T <: AbstractNFForm}(pm::GenericPowerModel{T}, n::Int=pm.cnw; bounded = true)
    if bounded  
        pm.var[:nw][n][:p] = @variable(pm.model, 
                                       [(l,i,j) in pm.ref[:nw][n][:arcs_from]], basename="$(n)_p",
                                       lowerbound = -pm.ref[:nw][n][:branch][l]["rate_a"], 
                                       upperbound = pm.ref[:nw][n][:branch][l]["rate_a"],
                                       start = PowerModels.getstart(pm.ref[:nw][n][:branch], l, "p_start"))
    else
        pm.var[:nw][n][:p] = @variable(pm.model, 
                                       [(l,i,j) in pm.ref[:nw][n][:arcs_from]], basename="$(n)_p",
                                       start = PowerModels.getstart(pm.ref[:nw][n][:branch], l, "p_start"))
    end

    p_expr = Dict{Any,Any}([((l,i,j), 1.0*p[(l,i,j)]) for (l,i,j) in pm.ref[:nw][n][:arcs_from]])
    p_expr = merge(p_expr, Dict([((l,j,i), -1.0*p[(l,i,j)]) for (l,i,j) in pm.ref[:nw][n][:arcs_from]]))
    pm.var[:nw][n][:p] = p_expr
end 

# objective definition
function objective_min_load_shed{T}(pm::GenericPowerModel{T}, n::Int=pm.cnw)
    c_pd = Dict(bp => 1 for bp in keys(pm.ref[:nw][n][:load]))
    for (i, load) in pm.ref[:nw][n][:load]
        if (load["pd"] < 0)
            c_pd[i] = 0
        end
    end
    ld = pm.var[:nw][n][:ld]
    @objective(pm.model, Min, sum(pm.ref[:nw][n][:load][i]["pd"] * c_pd[i] * ld[i] for i in keys(pm.ref[:nw][n][:load])))
end

# constraint templates 
function constraint_kcl_ls{T}(pm::GenericPowerModel{T}, n::Int=pm.cnw, i::Int)
    if !haskey(pm.con[:nw][n], :kcl_p)
        pm.con[:nw][n][:kcl_p] = Dict{Int,ConstraintRef}()
    end
    if !haskey(pm.con[:nw][n], :kcl_q)
        pm.con[:nw][n][:kcl_q] = Dict{Int,ConstraintRef}()
    end
    bus = ref(pm, n, :bus, i)
    bus_arcs = ref(pm, n, :bus_arcs, i)
    bus_arcs_dc = ref(pm, n, :bus_arcs_dc, i)
    bus_arcs_ne = ref(pm, n, :ne_bus_arcs, i)
    bus_gens = ref(pm, n, :bus_gens, i)
    bus_loads = ref(pm, n, :bus_loads, i)
    pd = Dict(k => v["pd"] for (k,v) in ref(pm, n, :load))
    qd = Dict(k => v["qd"] for (k,v) in ref(pm, n, :load))
    constraint_kcl_shunt(pm, n, i, bus_arcs, bus_arcs_dc, bus_gens, bus_loads, pd, qd)
end 

constraint_kcl_ls(pm::GenericPowerModel, i::Int) = constraint_kcl_ls(pm, pm.cnw, i::Int)

function constraint_ohms_from{T}(pm::GenericPowerModel{T}, n::Int, i::Int)
    branch = ref(pm, n, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = calc_branch_y(branch)

    constraint_ohms_y_from(pm, n, f_bus, t_bus, f_idx, t_idx, g, b)
end
constraint_ohms_y_from(pm::GenericPowerModel, i::Int) = constraint_ohms_y_from(pm, pm.cnw, i)

function constraint_ohms_y_to{T}(pm::GenericPowerModel{T}, n::Int, i::Int)
    branch = ref(pm, n, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = calc_branch_y(branch)

    constraint_ohms_y_to(pm, n, f_bus, t_bus, f_idx, t_idx, g, b)
end
constraint_ohms_y_to(pm::GenericPowerModel, i::Int) = constraint_ohms_y_to(pm, pm.cnw, i)


# overloaded constraint functions
function constraint_kcl_ls{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, n::Int, i, bus_arcs, bus_arcs_dc, bus_gens, bus_loads, pd, qd)
    pg = pm.var[:nw][n][:pg]
    p = pm.var[:nw][n][:p]
    p_dc = pm.var[:nw][n][:p_dc]
    ld = pm.var[:nw][n][:ld]
    load = pm.ref[:nw][n][:load]

    pm.con[:nw][n][:kcl_p][i] = @constraint(pm.model, sum(p[a] for a in bus_arcs) + sum(p_dc[a_dc] for a_dc in bus_arcs_dc) == sum(pg[g] for g in bus_gens) - sum(pd[d]*(1-ld[d]) for d in bus_loads))
    # omit reactive constraint
end

function constraint_kcl_shunt(pm::GenericPowerModel{T}, n::Int, i, bus_arcs, bus_arcs_dc, bus_gens, bus_loads, pd, qd) where T <: PowerModels.AbstractWRForm
    w = pm.var[:nw][n][:w][i]
    pg = pm.var[:nw][n][:pg]
    qg = pm.var[:nw][n][:qg]
    p = pm.var[:nw][n][:p]
    q = pm.var[:nw][n][:q]
    p_dc = pm.var[:nw][n][:p_dc]
    q_dc = pm.var[:nw][n][:q_dc]
    ld = pm.var[:nw][n][:ld]
    load = pm.ref[:nw][n][:load]

    @constraint(pm.model, sum(p[a] for a in bus_arcs) + sum(p_dc[a_dc] for a_dc in bus_arcs_dc) == sum(pg[g] for g in bus_gens) - sum(pd[d]*(1-ld[d]) for d in bus_loads))
    @constraint(pm.model, sum(q[a] for a in bus_arcs) + sum(q_dc[a_dc] for a_dc in bus_arcs_dc) == sum(qg[g] for g in bus_gens) - sum(qd[d]*(1-ld[d]) for d in bus_loads))
end

function constraint_kcl_shunt(pm::GenericPowerModel{T}, n::Int, i::Int, bus_arcs, bus_arcs_dc, bus_gens, bus_loads, pd, qd) where T <: AbstractACPForm
    vm = pm.var[:nw][n][:vm][i]
    p = pm.var[:nw][n][:p]
    q = pm.var[:nw][n][:q]
    pg = pm.var[:nw][n][:pg]
    qg = pm.var[:nw][n][:qg]
    p_dc = pm.var[:nw][n][:p_dc]
    q_dc = pm.var[:nw][n][:q_dc]
    ld = pm.var[:nw][n][:ld]

    pm.con[:nw][n][:kcl_p][i] = @constraint(pm.model, sum(p[a] for a in bus_arcs) + sum(p_dc[a_dc] for a_dc in bus_arcs_dc) == sum(pg[g] for g in bus_gens) - sum(pd[d]*(1-ld[d]) for d in bus_loads))
    pm.con[:nw][n][:kcl_q][i] = @constraint(pm.model, sum(q[a] for a in bus_arcs) + sum(q_dc[a_dc] for a_dc in bus_arcs_dc) == sum(qg[g] for g in bus_gens) - sum(qd[d]*(1-ld[d]) for d in bus_loads))
end

function constraint_ohms_from{T <: AbstractNFForm}(pm::GenericPowerModel{T}, n::Int, f_bus, t_bus, f_idx, t_idx, g, b)
     # Do nothing
end

function constraint_ohms_from{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, n::Int, f_bus, t_bus, f_idx, t_idx, g, b)
    p_fr = pm.var[:nw][n][:p][f_idx]
    va_fr = pm.var[:nw][n][:va][f_bus]
    va_to = pm.var[:nw][n][:va][t_bus]

    @constraint(pm.model, p_fr == -b*(va_fr - va_to))
    # omit reactive constraint
end

function constraint_ohms_to{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}, n::Int, f_bus, t_bus, f_idx, t_idx, g, b)
     # Do nothing, this model is symmetric
     return Set()
end

function constraint_ohms_from{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, n::Int, f_bus, t_bus, f_idx, t_idx, g, b)
    p_fr = pm.var[:nw][n][:p][f_idx]
    q_fr = pm.var[:nw][n][:q][f_idx]
    w_fr = pm.var[:nw][n][:w][f_bus]
    wr = pm.var[:nw][n][:wr][(f_bus, t_bus)]
    wi = pm.var[:nw][n][:wi][(f_bus, t_bus)]

    @constraint(pm.model, p_fr == g*w_fr + (-g*wr) + (-b*wi) )
    @constraint(pm.model, q_fr == -b*w_fr - (-b*wr) + (-g*wi) )
end

function constraint_ohms_to{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}, n::Int, f_bus, t_bus, f_idx, t_idx, g, b)
    q_to = pm.var[:nw][n][:q][t_idx]
    p_to = pm.var[:nw][n][:p][t_idx]
    w_to = pm.var[:nw][n][:w][t_bus]
    wr = pm.var[:nw][n][:wr][(f_bus, t_bus)]
    wi = pm.var[:nw][n][:wi][(f_bus, t_bus)]

    @constraint(pm.model, p_to == g*w_to + (-g*wr) + (b*wi) )
    @constraint(pm.model, q_to == -b*w_to - (-b*wr) + (g*wi) )
end

function constraint_ohms_from{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, n::Int, f_bus, t_bus, f_idx, t_idx, g, b)
    p_fr = pm.var[:nw][n][:p][f_idx]
    q_fr = pm.var[:nw][n][:q][f_idx]
    vm_fr = pm.var[:nw][n][:vm][f_bus]
    vm_to = pm.var[:nw][n][:vm][t_bus]
    va_fr = pm.var[:nw][n][:va][f_bus]
    va_to = pm.var[:nw][n][:va][t_bus]

    @NLconstraint(pm.model, p_fr == g*vm_fr^2 + -g*vm_fr*vm_to*cos(va_fr-va_to) + -b*vm_fr*vm_to*sin(va_fr-va_to) )
    @NLconstraint(pm.model, q_fr == -b*vm_fr^2 + b*vm_fr*vm_to*cos(va_fr-va_to) + -g*vm_fr*vm_to*sin(va_fr-va_to) )
end

function constraint_ohms_to{T <: PowerModels.AbstractACPForm}(pm::GenericPowerModel{T}, n::Int, f_bus, t_bus, f_idx, t_idx, g, b)
    p_to = pm.var[:nw][n][:p][t_idx]
    q_to = pm.var[:nw][n][:q][t_idx]
    vm_fr = pm.var[:nw][n][:vm][f_bus]
    vm_to = pm.var[:nw][n][:vm][t_bus]
    va_fr = pm.var[:nw][n][:va][f_bus]
    va_to = pm.var[:nw][n][:va][t_bus]

    @NLconstraint(pm.model, p_to == g*vm_to^2 + -g*vm_fr*vm_to*cos(va_to-va_fr) + -b*vm_fr*vm_to*sin(va_to-va_fr) )
    @NLconstraint(pm.model, q_to == -b*vm_to^2 + b*vm_fr*vm_to*cos(va_to-va_fr) + -g*vm_fr*vm_to*sin(va_to-va_fr) )
end
