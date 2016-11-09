using PowerModels
using Graphs

type Graph
    graph               ::SimpleGraph
    vertex_map          ::Dict{Int,Any}
    edge_map            ::Dict{Int,Any}
    bus_to_vertex_map   ::Dict{Int,Int}
    data                ::Dict{AbstractString,Any}
    sets                ::PowerModels.PowerDataSets
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

function parse_prob_file(file::ASCIIString, data::Dict{AbstractString,Any})

    file = string(split(file, ".m")[1], ".prob")
    data_string = readall(open(file))
    data_lines = split(data_string, '\n')
    parsed_matrices = []
    last_index = length(data_lines)
    index = 1

    while index <= last_index
        line = strip(data_lines[index])

        if length(line) <= 0 || strip(line)[1] == '%'
            index += 1
            continue
        end

        if contains(line, "[")
            matrix = PowerModels.parse_matrix(data_lines, index)
            push!(parsed_matrices, matrix)
            index += matrix["line_count"] - 1
        end
        index += 1
    end

    parsed_matrix = parsed_matrices[1]
    prob = []
    if parsed_matrix["name"] == "mpc.branchprobabilities"
        for row in parsed_matrix["data"]
            push!(prob, parse(Float64, row[3]))
        end
    end 
    
    for i in 1:length(prob)
        for branch in data["branch"]
            if branch["index"] == i
                branch["prob"] = prob[i]
                break 
            end 
        end 
    end 

    return 
end

function parse_layout_file(file)
    data_string = readall(open(file))
    data_lines = split(data_string, '\n')
    parsed_matrices = []
    last_index = length(data_lines)
    index = 1

    while index <= last_index
        line = strip(data_lines[index])

        if length(line) <= 0 || strip(line)[1] == '%'
            index += 1
            continue
        end

        if contains(line, "[")
            matrix = PowerModels.parse_matrix(data_lines, index)
            push!(parsed_matrices, matrix)
            index += matrix["line_count"] - 1
        end
        index += 1
    end

    parsed_matrix = parsed_matrices[1]
    bus_locations = []

    if parsed_matrix["name"] == "mpc.buslocation"

        for bus_row in parsed_matrix["data"]
            bus_data = Dict{AbstractString,Any}(
                                                "index" => parse(Int, bus_row[1]), 
                                                "x_coord" => parse(Float64, bus_row[2]),
                                                "y_coord" => parse(Float64, bus_row[3])
            )

            push!(bus_locations, bus_data)
        end
    end

    return bus_locations
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
    vertices_with_degree = [ v => out_degree(v, gm.graph) for v in vertices(gm.graph) ]
    vertices_with_degree = filter((v,deg) -> deg == degree, vertices_with_degree)
    neighbors = [ v => collect(out_edges(v, gm.graph)) for v in collect(keys(vertices_with_degree)) ]

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

function create_n_1_graph(gm::Graph, buses::Dict{Int,Any}, branches::Dict{Int,Any}, line)
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

function check_graph_for_isolation(gm::Graph, buses::Dict{Int,Any}, branches::Dict{Int,Any})
    components = connected_components(gm.graph)
    isolated_load_vertices = Attack[]
    if length(components) == 1
        return Attack[]
    end
    sets = gm.sets
    for component in components
        is_gen = false
        for v in component
            i = gm.vertex_map[v]["index"]
            if buses[i]["bus_type"] == 2 || buses[i]["bus_type"] == 3
                total_pmin = sum([abs(sets.gens[g]["pmin"]) for g in sets.bus_gens[i]])
                total_pmax = sum([abs(sets.gens[g]["pmax"]) for g in sets.bus_gens[i]])
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
