function solve_inner_problem(prob::Problem, c::Configuration, model=JuMP.Model())

    # initializing solver
    ipopt_optimizer = JuMP.with_optimizer(Ipopt.Optimizer, print_level=0, sb="yes")

    # deactivate the branches in prob.data 
    for index in get_current_solution(prob)
        prob.data["branch"][string(index)]["br_status"] = 0
    end 

    # post the dc load shedding model - ignore the dc lines and theta diff bounds
    @assert !haskey(prob.data, "multinetwork")
    @assert !haskey(prob.data, "conductors")

    result = run_mld(prob.data, PMs.DCPPowerModel, ipopt_optimizer; 
        setting = Dict("output" => Dict("branch_flows" => true)))

    # activate the branches in p.data 
    for index in get_current_solution(prob)
        prob.data["branch"][string(index)]["br_status"] = 1
    end 

    

    for (l,i,j) in ref[:arcs_from]
        (abs(getdual(p[(l,i,j)])) > 1.0) && debug(logger, "($l,$i,$j) -> $(getvalue(p[(l,i,j)])), $(getdual(p[(l,i,j)]))")
    end 

    set_current_incumbent(prob, getobjectivevalue(model))

    if (get_current_incumbent(prob) - get_best_incumbent(prob) > 1e-4) 
        set_best_solution(prob, get_current_solution(prob))
        set_best_incumbent(prob, get_current_incumbent(prob))
        (get_problem_type(c) == :planar) && (set_center_bus_id(prob))
        for (i, bus) in ref[:bus]
            bus_loads = [ref[:load][l] for l in ref[:bus_loads][i]]
            if (length(bus_loads) > 0)
                bus_load_shed = [getvalue(ld[load["index"]]) for load in bus_loads]
                bus_ld_obj = [ld_obj[load["index"]] for load in bus_loads]
                bus_pd = [load["pd"] for load in bus_loads]
                prob.bus_load_shed[i] = sum(bus_load_shed .* bus_ld_obj .* bus_pd)
            end
        end 
    end 

    update_opt_gap(prob)
    
    return time, status, model
end 

function get_inner_solution(prob::Problem, model)

    solution_dict = Dict{String,Any}()
    solution_dict["branch_flow"] = Dict{Any,Any}()
    solution_dict["va"] = Dict{Any,Any}()

    current_solution = get_current_solution(prob)
    p = getindex(model, :p)
    va = getindex(model, :va)

    ref = prob.ref
    
    for (l,i,j) in ref[:arcs_from]
        solution_dict["branch_flow"][(l,i,j)] = (l in current_solution) ? 0.0 : getvalue(p[(l,i,j)]) 
    end 

    for (i, bus) in ref[:bus]
        solution_dict["va"][i] = getvalue(va[i])
    end 

    return solution_dict
end 