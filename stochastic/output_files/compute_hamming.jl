
args = Dict{Any,Any}()
args["file"] = String(ARGS[1])
args["h_or_u"] = String(ARGS[2])
args["hcase"] = String(ARGS[3])
branches_h = Dict{Any,Any}()
branches = Dict{Any,Any}()


for k in 2:15
    if k <= 10
        f = open("$(args["file"])_$k")
        lines = readlines(f)
        branches[k] = Dict{AbstractString, Any}("soc" => Set(sort([parse(Int, branch) for branch in split(split(split(lines[4], "[")[2], "]")[1], ",")])))
    else
        f = open("$(args["file"])_$(k)_nonf")
        lines = readlines(f)
        branches[k] = Dict{AbstractString, Any}("soc" => Set(sort([parse(Int, branch) for branch in split(split(split(lines[3], "[")[2], "]")[1], ",")])))
    end 
    f_h = open("$(args["file"])_$(k)_soc_$(args["h_or_u"])$(args["hcase"])")
    lines_h = readlines(f_h)
    branches_h[k] = Dict{AbstractString, Any}("soc" => Set(sort([parse(Int, branch) for branch in split(split(split(lines_h[2], "[")[2], "]")[1], ",")])))
end

hamming_distance = zeros(14)

for k in 2:15
    hamming_distance[k-1] = length(intersect(branches_h[k]["soc"], branches[k]["soc"]))
end

for i in hamming_distance
    println(i)
end
