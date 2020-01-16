function solve_inner_problem(prob::Problem, c::Configuration)

    # initializing solver
    ipopt_optimizer = JuMP.with_optimizer(Ipopt.Optimizer, print_level=0, sb="yes")

    # deactivate the branches in prob.data 
    for index in get_current_solution(prob)
        prob.data["branch"][string(index)]["br_status"] = 0
    end 

    # post the dc load shedding model - ignore the dc lines and theta diff bounds
    @assert !haskey(prob.data, "multinetwork")
    @assert !haskey(prob.data, "conductors")

    result = Dict()
    if get_problem_type(c) == :dc
        result = run_mld(prob.data, PMs.DCPPowerModel, ipopt_optimizer; 
            setting = Dict("output" => Dict("branch_flows" => true)))
    end 
    if get_problem_type(c) == :soc
        result = run_mld(prob.data, PMs.SOCWRPowerModel, ipopt_optimizer; 
            setting = Dict("output" => Dict("branch_flows" => true)))
    end 

    # activate the branches in p.data 
    for index in get_current_solution(prob)
        prob.data["branch"][string(index)]["br_status"] = 1
    end 

    load_served = result["objective"] / result["solution"]["baseMVA"]
    total_load = get_total_load(prob)
    load_shed = total_load - load_served
    set_current_incumbent(prob,  load_shed)


    if (get_current_incumbent(prob) - get_best_incumbent(prob) > 1e-4) 
        set_best_solution(prob, get_current_solution(prob))
        set_best_incumbent(prob, get_current_incumbent(prob))
    end 

    update_opt_gap(prob)
    
    return result["solve_time"], result["termination_status"], result["solution"]
end 

function get_cut_coefficients(prob::Problem, config::Configuration, solution)

    solution_dict = Dict{String,Any}()
    solution_dict["branch_flow"] = Dict{Any,Any}()

    current_solution = get_current_solution(prob)

    ref = prob.ref
    baseMVA = solution["baseMVA"]
    @show solution["branch"]
    
    for (l,i,j) in ref[:arcs_from]
        if get_problem_type(config) == :dc
            if l in current_solution
                solution_dict["branch_flow"][(l,i,j)] = 0.0
            else 
                solution_dict["branch_flow"][(l,i,j)] = abs(solution["branch"][string(l)]["pf"])
            end
        end 
        if get_problem_type(config) == :soc
            if l in current_solution
                solution_dict["branch_flow"][(l,i,j)] = 0.0
            else 
                solution_dict["branch_flow"][(l,i,j)] = max(abs(solution["branch"][string(l)]["pf"]), 
                    abs(solution["branch"][string(l)]["pt"]))
            end
        end 
    end 

    return solution_dict
end 