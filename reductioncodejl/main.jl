using JuMP
import JSON
using Distributions
include("prob.jl")

function run_heuristic(; file = "../data/nesta_case24_ieee_rts_nk.m", k = 4)

    data = PowerModels.parse_file(file)
    buses = Dict([(parse(Int, k), v) for (k, v) in data["bus"]])
    buses = filter((i, bus) -> bus["bus_type"] != 4, buses)
    branches = Dict([(parse(Int, k), v) for (k, v) in data["branch"]])
    branches = filter((i, branch) -> branch["br_status"] == 1 && branch["f_bus"] in keys(buses) && branch["t_bus"] in keys(buses), branches)
    branch_indexes = collect(keys(branches))
    
    log_p = Dict([(i, log(branches[i]["prob"])) for i in branch_indexes])
    ref = PowerModels.build_ref(data)

    successful_attacks = Attack[]
    for branch in branches
        gm = Graph()
        gm.data = data
        gm.ref = ref
        create_n_1_graph(gm, buses, branches, branch)
        isolated_load_vertices = check_graph_for_isolation(gm, buses, branches)
        for load in isolated_load_vertices
            push!(load.branch_ids, branch[1])
            push!(successful_attacks, load)
        end
    end
    
    remove_redundant_attacks(successful_attacks)
    
    for i in 2:k
        if det_or_stoch == 1
            attack = create_and_solve_det_milp(data, ref, successful_attacks, k = i)
        else 
            attack = create_and_solve_stoch_milp(data, ref, successful_attacks, log_p, k = i)
        end 
        push!(successful_attacks, attack)
    end

    attack_sol = []
    for i in 1:length(successful_attacks)
        if length(successful_attacks[i].branch_ids) == 1
            continue
        else 
            attack_dict = Dict("k" => length(successful_attacks[i].branch_ids), 
                               "load" => successful_attacks[i].total_load, 
                               "branch_ids" => successful_attacks[i].branch_ids)
            push!(attack_sol, attack_dict)
            println("$(length(successful_attacks[i].branch_ids)) ... $(successful_attacks[i].total_load); branch_ids ... $([i for i in successful_attacks[i].branch_ids]); bus_ids ... $([i for i in successful_attacks[i].bus_ids])")
        end
    end
    json_dict = Dict{AbstractString,Any}()
    json_dict["attack"] = attack_sol
    json_string = JSON.json(json_dict)
    if det_or_stoch == 1
        write("det_isolation.json", json_string)
    else 
        write("stoch_isolation.json", json_string)
    end 
end

file = String(ARGS[1])
k = parse(Int, ARGS[2])
det_or_stoch = parse(Int, ARGS[3])
run_heuristic(file = file, k = k)
