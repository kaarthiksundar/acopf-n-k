using JuMP
using Distributions
using CPLEX
using PowerModels
using Ipopt
include("prob.jl")

function run_max_flow(; file = "../data/nesta_case24_ieee_rts.m", k = 4)

    data = PowerModels.parse_file(file)
    data, sets = PowerModels.process_raw_mp_data(data)
    buses = Dict(Int(bus["index"]) => bus for bus in data["bus"])
    buses = filter((i, bus) -> bus["bus_type"] != 4, buses)
    branches = Dict(Int(branch["index"]) => branch for branch in data["branch"])
    branches = filter((i, branch) -> branch["br_status"] == 1 && branch["f_bus"] in keys(buses) && branch["t_bus"] in keys(buses), branches)
    branch_indexes = collect(keys(branches))
    bus_indexes = collect(keys(buses))
    
    original_edges = branches
    original_edge_indexes = branch_indexes
    max_branch_index = maximum(branch_indexes)

    original_vertices = buses
    original_vertex_indexes = bus_indexes
    max_bus_index = maximum(bus_indexes)

    new_vertex_indexes = Int[]
    # source node
    push!(new_vertex_indexes, max_bus_index + 1)
    # terminal node
    push!(new_vertex_indexes, max_bus_index + 2)
    
    new_edges = Dict{Int, Any}()
    edge_id = max_branch_index + 1
    for (bus, gens) in sets.bus_gens
        gens_in_bus = length(gens)
        for i in 1:gens_in_bus
            if sets.gens[gens[i]]["pmax"] > 0.0
                edge = Dict{AbstractString, Any}("rate_a" => sets.gens[gens[i]]["pmax"], 
                                                 "f_bus" => new_vertex_indexes[1],
                                                 "t_bus" => bus)
                new_edges[edge_id] = edge 
                edge_id += 1
            end 
        end 
    end 
    
    for (i, bus) in buses
        if bus["pd"] > 0
            edge = Dict{AbstractString, Any}("rate_a" => bus["pd"], 
                                             "f_bus" => bus["index"],
                                             "t_bus" => new_vertex_indexes[2])
            new_edges[edge_id] = edge 
            edge_id += 1
        end 
    end 

    new_edge_indexes = collect(keys(new_edges))
    
    totalload = 0.0
    for (i,bus) in buses
        totalload += bus["pd"]
    end

    edges = sort(collect([original_edge_indexes; new_edge_indexes]))

    vertices = sort(collect([original_vertex_indexes; new_vertex_indexes]))
    
    m = Model(solver=CplexSolver())

    @variable(m, 0 <= w[i in edges] <= 1)
    
    cap = Dict{Int, Float64}()
    for i in edges
        if i in original_edge_indexes
            cap[i] = original_edges[i]["rate_a"]
        else
            cap[i] =  new_edges[i]["rate_a"]
        end 
    end 

    @variable(m, d[i in edges], Bin)
    @variable(m, r[i in vertices], Bin)

    @objective(m, Min, sum(cap[i]*w[i] for i in edges))
    
    @constraint(m, inactive[i in new_edge_indexes], d[i] == 0)
    @constraint(m, sum(d) == k)
    
    
    @constraint(m, cut_in_1[i in original_edge_indexes], r[original_edges[i]["t_bus"]] - r[original_edges[i]["f_bus"]] - w[i] - d[i] <= 0)
    @constraint(m, cut_in_2[i in original_edge_indexes], r[original_edges[i]["t_bus"]] - r[original_edges[i]["f_bus"]] + w[i] + d[i] >= 0)
    @constraint(m, cut_out_1[i in original_edge_indexes], r[original_edges[i]["f_bus"]] - r[original_edges[i]["t_bus"]] - w[i] - d[i] <= 0)
    @constraint(m, cut_out_2[i in original_edge_indexes], r[original_edges[i]["f_bus"]] - r[original_edges[i]["t_bus"]] + w[i] + d[i] >= 0)

    @constraint(m, extra_cut_1[i in new_edge_indexes], r[new_edges[i]["t_bus"]] - r[new_edges[i]["f_bus"]] - w[i] - d[i] <= 0)
    @constraint(m, extra_cut_2[i in new_edge_indexes], r[new_edges[i]["t_bus"]] - r[new_edges[i]["f_bus"]] + w[i] + d[i] >= 0)
    
    @constraint(m, r[new_vertex_indexes[1]] == 0)
    @constraint(m, r[new_vertex_indexes[2]] == 1)

    solve(m)
    load_shed = totalload - getobjectivevalue(m)
    d_vals = getvalue(d)
    w_vals = getvalue(w)
    final_lines = []
    cut_set_lines = []
    cut_set_cap = []
    for i in edges
        if d_vals[i] >= 0.9
            push!(final_lines, i)
        end
        if w_vals[i] >= 0.9
            push!(cut_set_lines, i)
            push!(cut_set_cap, cap[i])
        end 
    end

    println("max flow load shed ... $(load_shed)")
    println("solution = x* ... $(collect(final_lines))")
    # println("cut set lines = w* ... $(collect(cut_set_lines))")
    # println("cut set cap = cap* ... $(sort(collect(cut_set_cap)))")

    data = PowerModels.parse_file(file)
    for branch in data["branch"]
        for index in final_lines
            if Int(branch["index"]) == index
                branch["br_status"] = 0
            end
        end
    end
    pm = ACPPowerModel(data; solver = IpoptSolver(print_level=0))
    post_pfls(pm)
    status, solve_time = solve(pm)
    result = PowerModels.build_solution(pm, status, solve_time)
    println("full AC load shed ... $(result["objective"])")
    
end

args = Dict{Any,Any}()
println(ARGS[1])
args["file"] = string(ARGS[1])
args["k"] = parse(Int, ARGS[2])

run_max_flow(file = args["file"], k = args["k"])
