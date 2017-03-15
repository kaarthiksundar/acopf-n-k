using PowerModels
using Graphs

type Graph
    graph               ::SimpleGraph
    vertex_map          ::Dict{Int,Any}
    edge_map            ::Dict{Int,Any}
    bus_to_vertex_map   ::Dict{Int,Int}
    data                ::Dict{AbstractString,Any}
    ref                 ::Dict{Symbol,Any}
    function Graph()
        gm = new()
        gm.graph = simple_graph(0, is_directed=false)
        gm.vertex_map = Dict{Int,Any}()
        gm.edge_map = Dict{Int,Any}()
        gm.bus_to_vertex_map = Dict{Int,Int}()
        gm.data = Dict{AbstractString,Any}()
        return gm
    end
end

type VertexNeighbors
    id          ::Int
    edge_ids    ::Vector{Int}
    function VertexNeighbors()
        vn = new()
        vn.id = 0
        vn.edge_ids = Int[]
        return vn
    end
end

type Attack
    bus_ids             ::Vector{Int}
    branch_ids          ::Vector{Int}
    total_load          ::Float64
    function Attack()
        a = new()
        a.bus_ids = Int[]
        a.branch_ids = Int[]
        a.total_load = 0.0
        return a
    end
end

function populate_gm(gm::Graph, buses::Dict{Int,Any}, branches::Dict{Int,Any})
    i = 1
    for bus in buses
        add_vertex!(gm.graph)
        key = bus[1]
        value = bus[2]
        gm.vertex_map[i] = value
        gm.bus_to_vertex_map[key] = i
        i += 1
    end

    i = 1
    for (key,value) in branches
        add_edge!(gm.graph, gm.bus_to_vertex_map[value["f_bus"]], gm.bus_to_vertex_map[value["t_bus"]]) 
        gm.edge_map[i] = value
        i += 1
    end

    for edge in edges(gm.graph)
        @assert gm.vertex_map[edge.source]["index"] == gm.edge_map[edge.index]["f_bus"]
        @assert gm.vertex_map[edge.target]["index"] == gm.edge_map[edge.index]["t_bus"]
    end
    return
end

function get_vertices(gm::Graph; degree = 1)
    vertices_with_degree = Dict(v => out_degree(v, gm.graph) for v in vertices(gm.graph))
    vertices_with_degree = filter((v,deg) -> deg == degree, vertices_with_degree)
    neighbors = Dict(v => collect(out_edges(v, gm.graph)) for v in collect(keys(vertices_with_degree)))

    vertex_neighbors = VertexNeighbors[]
    for (v,n) in neighbors
        if gm.vertex_map[v]["bus_type"] == 2 || gm.vertex_map[v]["bus_type"] == 3
            continue
        end
        vn = VertexNeighbors()
        vn.id = gm.vertex_map[v]["index"]
        for edge in n
            push!(vn.edge_ids, gm.edge_map[edge.index]["index"])
        end
        push!(vertex_neighbors, vn)
    end

    return vertex_neighbors
end

function create_n_1_graph(gm::Graph, buses, branches, line)
    i = 1
    for bus in buses
        add_vertex!(gm.graph)
        key = bus[1]
        value = bus[2]
        gm.vertex_map[i] = value
        gm.bus_to_vertex_map[key] = i
        i += 1
    end

    i = 1
    for branch in branches
        if branch == line
            continue
        end
        key = branch[1]
        value = branch[2]
        add_edge!(gm.graph, gm.bus_to_vertex_map[value["f_bus"]], gm.bus_to_vertex_map[value["t_bus"]]) 
        gm.edge_map[i] = value
        i += 1
    end

    for edge in edges(gm.graph)
        @assert gm.vertex_map[edge.source]["index"] == gm.edge_map[edge.index]["f_bus"]
        @assert gm.vertex_map[edge.target]["index"] == gm.edge_map[edge.index]["t_bus"]
    end

    return
end

function check_graph_for_isolation(gm::Graph, buses, branches)
    components = connected_components(gm.graph)
    isolated_load_vertices = Attack[]
    if length(components) == 1
        return Attack[]
    end
    ref = gm.ref
    for component in components
        is_gen = false
        for v in component
            i = gm.vertex_map[v]["index"]
            if buses[i]["bus_type"] == 2 || buses[i]["bus_type"] == 3
                total_pmin = sum([abs(ref[:gen][g]["pmin"]) for g in ref[:bus_gens][i]])
                total_pmax = sum([abs(ref[:gen][g]["pmax"]) for g in ref[:bus_gens][i]])
                is_condensor = (total_pmin == 0 && total_pmax == 0) ? true : false
                if is_condensor
                    continue
                else
                    is_gen = true
                    break
                end
            end
        end
        if !(is_gen)
            load = Attack()
            for v in component
                push!(load.bus_ids, gm.vertex_map[v]["index"])
                load.total_load += abs(buses[gm.vertex_map[v]["index"]]["pd"])
            end
            push!(isolated_load_vertices, load)

        end
    end

    return isolated_load_vertices
end

function remove_redundant_attacks(attacks::Vector{Attack})
    redundant_attack_indexes = Set()
    num_attacks = length(attacks)
    for i in 1:num_attacks
        for j in 1:num_attacks
            if j == i 
                continue
            end
            num_elements_i = length(attacks[i].bus_ids)
            num_elements_j = length(attacks[j].bus_ids)
            attack_set_i = Set(attacks[i].bus_ids)
            attack_set_j = Set(attacks[j].bus_ids)
            intersection = intersect(attack_set_i, attack_set_j)
            if attack_set_i == intersection
                push!(redundant_attack_indexes, i)
            end
            if attack_set_j == intersection
                push!(redundant_attack_indexes, j)
            end
        end
    end
    deleteat!(attacks, sort(collect(redundant_attack_indexes)))
    return
end
