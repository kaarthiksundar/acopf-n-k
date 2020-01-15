function populate_model(p::Problem, c::Configuration)
    
    JuMP.@variable(p.model, x[keys(p.ref[:branch])], Bin)
    JuMP.@constraint(p.model, budget, sum(x) == get_k(c))
    JuMP.@variable(p.model, 0 <= eta <= 1e4)
    JuMP.@variable(p.model, prob <= 0)
    JuMP.@variable(p.model, y <= 1e6)

    log_p = Dict([(i, log(p.ref[:branch][i]["prob"])) for i in keys(p.ref[:branch])])
    JuMP.@constraint(p.model, prob == sum(x[i]*log_p[i] for i in keys(p.ref[:branch])))

    JuMP.@objective(p.model, Max, y)
    
    return 
end 

function add_cutting_plane(p::Problem, sol::Dict{String,Any})
    # current_solution = get_current_solution(p)
    # x = getindex(p.model, :x)
    # eta = getindex(p.model, :eta)
    # prob = getindex(p.model, :prob)
    # y = getindex(p.model, :y)
    # load_shed = get_current_incumbent(p)

    # eta_val = getvalue(eta)
    #     p_val = getvalue(p)
    #     if eta_val > 0.0
    #         inv_eta_val = 1/eta_val
    #         @lazyconstraint(cb, y <= p + log(eta_val) + inv_eta_val*(eta - eta_val))
    #     end

    # flow = sol["branch_flow"]
    # dual_bounds = get_dual_bounds(p)

    # var = Any[] 
    # coeff = Any[]
    # constant = load_shed

    # for (i, branch) in p.ref[:branch]
    #     f_bus = branch["f_bus"]
    #     t_bus = branch["t_bus"]
    #     arc = (i, branch["f_bus"], branch["t_bus"])
    #     g, b = PMs.calc_branch_y(branch)
    #     if !(i in current_solution) 
    #         push!(var, x[i])
    #         flow_bound = (flow[arc] > 0) ? dual_bounds[i][:ub] : dual_bounds[i][:lb]
    #         flow_val = round(abs(flow[arc]) * flow_bound; digits=4)
    #         push!(coeff, flow_val)
    #     end 
    # end 

    # expr = AffExpr(var, coeff, constant)

    # @constraint(p.model, eta <= expr)
    
    return 
end 