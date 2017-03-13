using PowerModels

function get_cut_coefficients{T <: PowerModels.AbstractDCPForm}(pm::GenericPowerModel{T}; cut_constructor = "DC")
    branches = pm.ref[:branch]
    branch_indexes = keys(branches)
    alpha = Dict(i => 0.0 for i in branch_indexes)
    p = getvariable(pm.model, :p)
    for (i, branch) in branches
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        f_idx = (i, f_bus, t_bus)
        t_idx = (i, t_bus, f_bus)
        p_max = getvalue(p[f_idx])
        alpha[i] = abs(p_max)
    end
    return alpha
end

function get_cut_coefficients{T <: PowerModels.AbstractWRForm}(pm::GenericPowerModel{T}; cut_constructor = "DC")
    branches = pm.ref[:branch]
    branch_indexes = keys(branches)
    alpha = Dict(i => 0.0 for i in branch_indexes)
    gen_indexes = keys(pm.ref[:gen])
    p = getvariable(pm.model, :p)
    q = getvariable(pm.model, :q)
    for (i, branch) in branches
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        f_idx = (i, f_bus, t_bus)
        t_idx = (i, t_bus, f_bus)
        p_max = max(abs(getvalue(p[f_idx])), abs(getvalue(p[t_idx])))
        q_max = max(abs(getvalue(q[f_idx])), abs(getvalue(q[t_idx])))
        p_temp = 0.0
        
        if (cut_constructor == "AC")
        for (j, bus) in pm.ref[:bus]
                if (bus["pd"] > 0 && bus["pd"] >= q_max)
                    ld_temp = 1 - q_max/bus["pd"]
                    p_temp = max(p_temp, bus["pd"]*(1-ld_temp))
                end
            end
        end

        alpha[i] = max(p_max, p_temp)
    end

    return alpha
end
