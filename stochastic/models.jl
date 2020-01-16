function populate_model(p::Problem, c::Configuration)
    
    JuMP.@variable(p.model, x[keys(p.ref[:branch])], Bin)
    JuMP.@constraint(p.model, budget, sum(x) == get_k(c))
    JuMP.@variable(p.model, 0 <= eta <= 1e4)
    JuMP.@variable(p.model, prob <= 0)
    JuMP.@variable(p.model, y <= 1e6)

    log_p = Dict([(i, log(p.ref[:branch][i]["prob"])) for i in keys(p.ref[:branch])])
    JuMP.@constraint(p.model, prob == sum(x[i]*log_p[i] for i in keys(p.ref[:branch])))

    JuMP.@objective(p.model, Max, y)

    function outer_approximate(cb)
        eta_val = MOI.get(
            JuMP.backend(JuMP.owner_model(eta)), 
            MOI.CallbackVariablePrimal(cb), JuMP.index(eta)
        )
        prob_val = MOI.get(
            JuMP.backend(JuMP.owner_model(prob)), 
            MOI.CallbackVariablePrimal(cb), JuMP.index(prob)
        )
        if eta_val > 0.0
            inv_eta_val = 1/eta_val
            con = JuMP.@build_constraint(y <= prob + log(eta_val) + inv_eta_val*(eta - eta_val))
            MOI.submit(p.model, MOI.LazyConstraint(cb), con)
        end
    end

    MOI.set(p.model, MOI.LazyConstraintCallback(), outer_approximate)
    
    return 
end 

function add_cutting_plane(p::Problem, sol::Dict{String,Any})

    return 
end 

function add_no_good_cut(p::Problem, c::Configuration)

    return 
end