using PowerModels 

function parse_prob_file(file::String, data::Dict{AbstractString,Any})

    file = string(split(file, ".m")[1], ".prob")
    data_string = readstring(open(file))
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

