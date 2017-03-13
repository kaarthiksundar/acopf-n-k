using JuMP
using Ipopt
using CPLEX
using Gurobi
using PowerModels
include("prob.jl")
include("cut.jl")
include("misc.jl")

function master_problem(; file = "../data/nesta_case24_ieee_rts.m", k = 4, solver = IpoptSolver(), model_constructor = SOCWRPowerModel, cut_constructor = "AC", m_type="OPF")

    data = PowerModels.parse_file(file)
    buses = [ Int(bus["index"]) => bus for bus in data["bus"] ]
    num_buses = length(buses)
    buses = filter((i, bus) -> bus["bus_type"] != 4, buses)
    branches = [ Int(branch["index"]) => branch for branch in data["branch"] ]
    branches = filter((i, branch) -> branch["br_status"] == 1 && branch["f_bus"] in keys(buses) && branch["t_bus"] in keys(buses), branches)
    branch_indexes = collect(keys(branches))
    
    initial_feasible_solution = Dict{AbstractString, Any}()
    json_data_string = 0
    if file == "../data/nesta_case73_ieee_rts.m"
        json_data_string = readall(open("det_isolation_73.json"))
    elseif file == "../data/nesta_case24_ieee_rts.m"
        json_data_string = readall(open("det_isolation_24.json"))
    else
        println("no start solution")
    end 

    if file == "../data/nesta_case73_ieee_rts__api.m"
        json_data_string = readall(open("det_isolation_73_api.json"))
    elseif file == "../data/nesta_case24_ieee_rts__api.m"
        json_data_string = readall(open("det_isolation_24_api.json"))
    else
        println("no start solution")
    end 
    
    if file == "../data/nesta_case73_ieee_rts__sad.m"
        json_data_string = readall(open("det_isolation_73_sad.json"))
    elseif file == "../data/nesta_case24_ieee_rts__sad.m"
        json_data_string = readall(open("det_isolation_24_sad.json"))
    else
        println("no start solution")
    end 
    
    if json_data_string != 0
        initial_feasible_solution = JSON.parse(json_data_string, dicttype = Dict{AbstractString,Any})
    end 

    totalload = 0.0
    for (i,bus) in buses
        totalload += bus["pd"]
    end
    # println("total load: $totalload ...")

    if m_type == "OTS"
        @assert model_constructor == DCPPowerModel 
    end 
    if model_constructor == DCPPowerModel
        cut_constructor = "DC"
    end

    # master_problem = Model(solver=GurobiSolver(LogToConsole=0))
    master_problem = Model(solver=CplexSolver())
    @variable(master_problem, 0 <= eta <= 1e6)
    @variable(master_problem, x[i in branch_indexes], Bin)

    @constraint(master_problem, sum(x) == k)

    @objective(master_problem, Max, eta)

    # anonymous function
    x_val = i -> getvalue(x[i])
    
    zlb = 0
    zub = 1e10
    eps = 1e-6

    iteration = 0
    final_xvals = Dict{Any,Any}
    final_lines = Any[]
    current_lines = Any[]

    if length(initial_feasible_solution) != 0
        for value in initial_feasible_solution["attack"]
            if value["k"] == k
                current_lines = value["branch_ids"]
                break
            end 
        end
        data = PowerModels.parse_file(file)
        for branch in data["branch"]
            for index in current_lines
                if Int(branch["index"]) == index
                    branch["br_status"] = 0
                end
            end
        end
        pm = model_constructor(data; solver = solver)
        if m_type != "OTS"
            post_pfls(pm)
        else
            post_ots(pm)
        end 
        status, solve_time = solve(pm)
        result = PowerModels.build_solution(pm, status, solve_time)
        alpha = get_cut_coefficients(pm, cut_constructor = cut_constructor)
        zlb = result["objective"]
        @constraint(master_problem, eta <= result["objective"] + sum{alpha[i]*x[i], i in collect(keys(alpha))})
    end
    
    final_lines = current_lines
    tic()
    solve(master_problem)

    zub = getobjectivevalue(master_problem)
    
    println("ub: $zub, lb: $zlb")

    while (zub - zlb > 0.01*zlb)
        iteration += 1
        current_xvals = [ i => x_val(i) for i in branch_indexes]
        current_lines = collect(keys(filter( (i, xval) -> xval > 1e-4, current_xvals)))
        data = PowerModels.parse_file(file)
        for branch in data["branch"]
            for index in current_lines
                if Int(branch["index"]) == index
                    branch["br_status"] = 0
                end
            end
        end
        pm = model_constructor(data; solver = solver)
        if m_type != "OTS"
            post_pfls(pm)
        else
            post_ots(pm)
        end 
        status, solve_time = solve(pm)
        result = PowerModels.build_solution(pm, status, solve_time)
        # println(result)
        alpha = get_cut_coefficients(pm, cut_constructor = cut_constructor)
        # println(getvalue(getvariable(pm.model, :line_z)))
        sub_objective = result["objective"]
        sub_lb = sub_objective
        if (sub_lb - zlb > eps)
            zlb = sub_lb
            final_xvals = current_xvals
            final_lines = current_lines
        end
        expr = zero(AffExpr)
        for i in branch_indexes
            if (current_xvals[i] <= eps)
                append!(expr, 1-x[i])
            else
                append!(expr, x[i])
            end
        end
        @constraint(master_problem, expr <= length(branch_indexes)-1)
        @constraint(master_problem, eta <= sub_objective + sum{alpha[i]*x[i], i in collect(keys(alpha))})
        solve(master_problem)
        zub = getobjectivevalue(master_problem)
        println("ub: $zub, lb: $zlb")
    end

    # independent_load_shed = get_independent_load_shed(file = file, solver = solver, model_constructor = model_constructor, lines = final_lines)
    println("###################################")
    println("k ... $k") 
    println("solution = x* ... $(collect(final_lines))")
    println("model: $(model_constructor), cut_type: $(cut_constructor), model_type: $(m_type)")
    println("total number of iterations ... $iteration")
    println("solution cost ... $zlb")
    time_taken = toq()
    println("computation time ... $time_taken")
    #println("independent load shed values ... $independent_load_shed")
    #println("sum of n-1 load sheds ... $(sum(values(independent_load_shed)))")

    # solving the AC load shed model on the final set of lines
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
    #println(result)
    println("full AC load shed ... $(result["objective"])")
    println("###################################")
    
    solution = Dict{AbstractString,Any}("k" => k, "lines" => collect(final_lines), 
                                        "model" => model_constructor, "time" => time_taken,
                                        "cut" => cut_constructor, "load_shed" => zlb, 
                                        "ac_load_shed" => result["objective"], "iterations" => iteration)
    push!(solution_vector, solution)
    
    return num_buses
end

solution_dict = Dict{AbstractString,Any}()
solution_vector = Any[] 
args = Dict{Any,Any}()
println(ARGS[1])
args["file"] = string(ARGS[1])
args["k"] = parse(Int, ARGS[2])

# master_problem(file = args["file"], k = args["k"], solver = IpoptSolver(print_level=5), model_constructor = args["model"], cut_constructor = args["cut"])
num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = DCPPowerModel, cut_constructor = "DC")
num_buses = master_problem(file = args["file"], k = args["k"], solver = GurobiSolver(), model_constructor = SOCWRPowerModel, cut_constructor = "DC")
# num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = SOCWRPowerModel, cut_constructor = "AC")

# model_constructor = DCPPowerModel/DCPLLPowerModel/SOCWRPowerModel; cut_constructor = "DC"/"AC"

solution_dict["solution"] = solution_vector 
json_string = JSON.json(solution_dict)

if endswith(args["file"], "api.m")
    write("./json_files/det_$(args["k"])_$(num_buses)_api.json", json_string)
elseif endswith(args["file"], "sad.m")
    write("./json_files/det_$(args["k"])_$(num_buses)_sad.json", json_string)
else
    write("./json_files/det_$(args["k"])_$(num_buses).json", json_string)
end
