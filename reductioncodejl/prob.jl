using JuMP
using Gurobi
using CPLEX
include("io.jl")

function create_and_solve_det_milp(data::Dict{AbstractString,Any}, sets::PowerModels.PowerDataSets, attacks::Vector{Attack}; k = 2)
    
    ϵ = 1e-5
    m = Model()
    save_model = Model()
    # setsolver(m, GurobiSolver(LogToConsole=0))
    # setsolver(m, GurobiSolver())
    setsolver(m, CplexSolver(CPX_PARAM_PREIND=0))
    
    notgen_bus_indexes = Int[] # includes plain buses, buses with loads and condensors
    gen_bus_indexes = Int[] # includes only generators and not condensors

    w_vertex = Dict{Int,Float64}()
    for i in sets.bus_indexes
        buses = sets.buses
        if buses[i]["bus_type"] == 2 || buses[i]["bus_type"] == 3
            total_pmin = sum([abs(sets.gens[g]["pmin"]) for g in sets.bus_gens[i]])
            total_pmax = sum([abs(sets.gens[g]["pmax"]) for g in sets.bus_gens[i]])
            is_condensor = (total_pmin == 0 && total_pmax == 0) ? true : false
            if is_condensor
                w_vertex[i] = abs(buses[i]["pd"])
                push!(notgen_bus_indexes, i)
                continue
            else
                w_vertex[i] = 0.0
                push!(gen_bus_indexes, i)
                continue
            end
        else
            w_vertex[i] = abs(buses[i]["pd"])
            push!(notgen_bus_indexes, i)
        end
    end
    
    @variable(m, x[i in sets.branch_indexes], Bin) # x[e] = 1 means the edge is removed
    @variable(m, y[v in sets.bus_indexes], Bin) # y[v] = 1 means the vertex is isolated
    @variable(m, dummy_edge[v in gen_bus_indexes] == 0) # dummy edges are added between a source and a gen_bus

    w_edge = [ i => 1 for i in sets.branch_indexes ]
    @constraint(m, gen_off[v in gen_bus_indexes], y[v] == 0)
    @constraint(m, sum{w_edge[i]*x[i], i in sets.branch_indexes} <= k)
    @objective(m, Max, sum{w_vertex[i]*y[i], i in sets.bus_indexes})

    index_map = IndexMap()
    for i in 1:length(sets.bus_indexes)
        index_map.bus_to_vertex[sets.bus_indexes[i]] = i
        index_map.vertex_to_bus[i] = sets.bus_indexes[i]
    end
    index_map.bus_to_vertex[0] = length(sets.bus_indexes) + 1
    index_map.vertex_to_bus[length(sets.bus_indexes)+1] = 0
    
    function lazycuts(cb)
        x_vals = [ i => getvalue(x[i]) for i in sets.branch_indexes ]
        y_vals = [ v => getvalue(y[v]) for v in notgen_bus_indexes ]
        y_vals = filter((v, val) -> val >= (1-ϵ), y_vals)
        g = simple_graph(length(keys(index_map.vertex_to_bus)), is_directed=false)
        dists = Float64[]
        # create support graph edges
        for (key, value) in x_vals
            f_bus = sets.branches[key]["f_bus"] 
            t_bus = sets.branches[key]["t_bus"] 
            i = index_map.bus_to_vertex[f_bus]
            j = index_map.bus_to_vertex[t_bus]
            add_edge!(g, i, j)
            if !haskey(index_map.parallel_edges, (i, j))
                index_map.parallel_edges[(i, j)] = Dict{AbstractString, Any}("count" => 1, "index" => [key])
                index_map.parallel_edges[(j, i)] = Dict{AbstractString, Any}("count" => 1, "index" => [key])
            else
                index_map.parallel_edges[(i, j)]["count"] += 1
                push!(index_map.parallel_edges[(i, j)]["index"], key)
                index_map.parallel_edges[(j, i)]["count"] += 1
                push!(index_map.parallel_edges[(j, i)]["index"], key)
            end
            push!(dists, value)
        end 
        # create support graph dummy edges
        for gen in gen_bus_indexes 
            f_bus = 0
            t_bus = gen
            i = index_map.bus_to_vertex[f_bus]
            j = index_map.bus_to_vertex[t_bus]
            add_edge!(g, i, j)
            if !haskey(index_map.parallel_edges, (i, j))
                index_map.parallel_edges[(i, j)] = Dict{AbstractString, Any}("count" => 1, "index" => [0])
                index_map.parallel_edges[(j, i)] = Dict{AbstractString, Any}("count" => 1, "index" => [0])
            end
            push!(dists, 0.0)
        end
        r = dijkstra_shortest_paths(g, dists, index_map.bus_to_vertex[0])
        paths = enumerate_indices(r.parent_indices, [index_map.bus_to_vertex[i] for i in keys(y_vals)])
        for path in paths
            target_bus = index_map.vertex_to_bus[path[length(path)]]
            @assert path[1] == length(sets.bus_indexes)+1
            @assert target_bus in notgen_bus_indexes
            @assert target_bus in keys(y_vals)
            path_indexes = Int[]
            for i in 2:length(path)-1
                path_index = 0.0
                index = index_map.parallel_edges[(path[i], path[i+1])] 
                if index["count"] > 1
                    path_index = (x_vals[index["index"][1]] > 1-ϵ) ? index["index"][2] : index["index"][1]
                else 
                    path_index = index["index"][1]
                end 
                push!(path_indexes, path_index)
            end

            if sum([x_vals[i] for i in path_indexes]) < y_vals[target_bus]
                @lazyconstraint(cb, sum{x[i], i in path_indexes} >= y[target_bus])
            end
        end 
    end
    
    addlazycallback(m, lazycuts)
    status = solve(m)
    x_vals = [ i => getvalue(x[i]) for i in sets.branch_indexes ]
    x_vals = filter((i, val) -> val > (1-ϵ), x_vals)
    y_vals = [ i => getvalue(y[i]) for i in notgen_bus_indexes ]
    y_vals = filter((i, val) -> val > (1-ϵ), y_vals)
    attack = Attack()
    for bus_id in collect(keys(y_vals))
        push!(attack.bus_ids, bus_id)
    end
    for branch_id in collect(keys(x_vals))
        push!(attack.branch_ids, branch_id)
    end 
    attack.total_load = getobjectivevalue(m)
    return attack 
end

function create_and_solve_stoch_milp(data::Dict{AbstractString,Any}, sets::PowerModels.PowerDataSets, attacks::Vector{Attack}, log_p::Dict{Any,Any}; k = 2)
    
    ϵ = 1e-5
    m = Model()
    save_model = Model()
    setsolver(m, CplexSolver(CPX_PARAM_PREIND=0))
    
    notgen_bus_indexes = Int[] # includes plain buses, buses with loads and condensors
    gen_bus_indexes = Int[] # includes only generators and not condensors

    w_vertex = Dict{Int,Float64}()
    for i in sets.bus_indexes
        buses = sets.buses
        if buses[i]["bus_type"] == 2 || buses[i]["bus_type"] == 3
            total_pmin = sum([abs(sets.gens[g]["pmin"]) for g in sets.bus_gens[i]])
            total_pmax = sum([abs(sets.gens[g]["pmax"]) for g in sets.bus_gens[i]])
            is_condensor = (total_pmin == 0 && total_pmax == 0) ? true : false
            if is_condensor
                w_vertex[i] = abs(buses[i]["pd"])
                push!(notgen_bus_indexes, i)
                continue
            else
                w_vertex[i] = 0.0
                push!(gen_bus_indexes, i)
                continue
            end
        else
            w_vertex[i] = abs(buses[i]["pd"])
            push!(notgen_bus_indexes, i)
        end
    end
    
    @variable(m, x[i in sets.branch_indexes], Bin) # x[e] = 1 means the edge is removed
    @variable(m, y[v in sets.bus_indexes], Bin) # y[v] = 1 means the vertex is isolated
    @variable(m, dummy_edge[v in gen_bus_indexes] == 0) # dummy edges are added between a source and a gen_bus
    @variable(m, p <= 0)
    @variable(m, z <= 1e6)
    @variable(m, 1e-6 <= eta <= 1e6)

    w_edge = [ i => 1 for i in sets.branch_indexes ]
    @constraint(m, gen_off[v in gen_bus_indexes], y[v] == 0)
    @constraint(m, sum{w_edge[i]*x[i], i in sets.branch_indexes} <= k)
    @constraint(m, p == sum{ x[i]*log_p[i], i in sets.branch_indexes})
    @constraint(m, eta == sum{w_vertex[i]*y[i], i in sets.bus_indexes})
    @objective(m, Max, z)

    index_map = IndexMap()
    for i in 1:length(sets.bus_indexes)
        index_map.bus_to_vertex[sets.bus_indexes[i]] = i
        index_map.vertex_to_bus[i] = sets.bus_indexes[i]
    end
    index_map.bus_to_vertex[0] = length(sets.bus_indexes) + 1
    index_map.vertex_to_bus[length(sets.bus_indexes)+1] = 0
    
    function lazycuts(cb)    
        eta_val = getvalue(eta)
        p_val = getvalue(p)
        if eta_val < ϵ
            eta_val = 0.01
        end
        if eta_val > 0.0
            inv_eta_val = 1/eta_val
            @lazyconstraint(cb, z <= p + log(eta_val) + inv_eta_val*(eta - eta_val))
        end

        x_vals = [ i => getvalue(x[i]) for i in sets.branch_indexes ]
        y_vals = [ v => getvalue(y[v]) for v in notgen_bus_indexes ]
        y_vals = filter((v, val) -> val >= (1-ϵ), y_vals)
        g = simple_graph(length(keys(index_map.vertex_to_bus)), is_directed=false)
        dists = Float64[]
        # create support graph edges
        for (key, value) in x_vals
            f_bus = sets.branches[key]["f_bus"] 
            t_bus = sets.branches[key]["t_bus"] 
            i = index_map.bus_to_vertex[f_bus]
            j = index_map.bus_to_vertex[t_bus]
            add_edge!(g, i, j)
            if !haskey(index_map.parallel_edges, (i, j))
                index_map.parallel_edges[(i, j)] = Dict{AbstractString, Any}("count" => 1, "index" => [key])
                index_map.parallel_edges[(j, i)] = Dict{AbstractString, Any}("count" => 1, "index" => [key])
            else
                index_map.parallel_edges[(i, j)]["count"] += 1
                push!(index_map.parallel_edges[(i, j)]["index"], key)
                index_map.parallel_edges[(j, i)]["count"] += 1
                push!(index_map.parallel_edges[(j, i)]["index"], key)
            end
            push!(dists, value)
        end 
        # create support graph dummy edges
        for gen in gen_bus_indexes 
            f_bus = 0
            t_bus = gen
            i = index_map.bus_to_vertex[f_bus]
            j = index_map.bus_to_vertex[t_bus]
            add_edge!(g, i, j)
            if !haskey(index_map.parallel_edges, (i, j))
                index_map.parallel_edges[(i, j)] = Dict{AbstractString, Any}("count" => 1, "index" => [0])
                index_map.parallel_edges[(j, i)] = Dict{AbstractString, Any}("count" => 1, "index" => [0])
            end
            push!(dists, 0.0)
        end
        r = dijkstra_shortest_paths(g, dists, index_map.bus_to_vertex[0])
        paths = enumerate_indices(r.parent_indices, [index_map.bus_to_vertex[i] for i in keys(y_vals)])
        for path in paths
            target_bus = index_map.vertex_to_bus[path[length(path)]]
            @assert path[1] == length(sets.bus_indexes)+1
            @assert target_bus in notgen_bus_indexes
            @assert target_bus in keys(y_vals)
            path_indexes = Int[]
            for i in 2:length(path)-1
                path_index = 0.0
                index = index_map.parallel_edges[(path[i], path[i+1])] 
                if index["count"] > 1
                    path_index = (x_vals[index["index"][1]] > 1-ϵ) ? index["index"][2] : index["index"][1]
                else 
                    path_index = index["index"][1]
                end 
                push!(path_indexes, path_index)
            end

            if sum([x_vals[i] for i in path_indexes]) < y_vals[target_bus]
                @lazyconstraint(cb, sum{x[i], i in path_indexes} >= y[target_bus])
            end
        end 
    end
    
    addlazycallback(m, lazycuts)
    status = solve(m)
    x_vals = [ i => getvalue(x[i]) for i in sets.branch_indexes ]
    x_vals = filter((i, val) -> val > (1-ϵ), x_vals)
    y_vals = [ i => getvalue(y[i]) for i in notgen_bus_indexes ]
    y_vals = filter((i, val) -> val > (1-ϵ), y_vals)
    p_val = getvalue(p)
    actual_prob = exp(p_val)
    log_eta = getobjectivevalue(m) - p_val 
    eta_val = exp(log_eta)
    exp_load_shed = actual_prob*eta_val 
    attack = Attack()
    for bus_id in collect(keys(y_vals))
        push!(attack.bus_ids, bus_id)
    end
    for branch_id in collect(keys(x_vals))
        push!(attack.branch_ids, branch_id)
    end 
    attack.total_load = exp_load_shed 
    return attack 
end

type IndexMap
    bus_to_vertex::Dict{Int,Int}
    vertex_to_bus::Dict{Int,Int}
    parallel_edges::Dict{Any,Any}
    function IndexMap()
        imap = new()
        imap.bus_to_vertex = Dict{Int,Int}()
        imap.vertex_to_bus = Dict{Int,Int}()
        imap.parallel_edges = Dict{Any,Any}()
        return imap
    end 
end 