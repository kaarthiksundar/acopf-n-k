using JuMP
using Ipopt
using CPLEX
#using Gurobi
using Distributions

include("prob.jl")
include("cut.jl")

function master_problem(; file = "../data/nesta_case24_ieee_rts_nk.m", k = 4, solver = IpoptSolver(), model_constructor = SOCWRPowerModel, cut_constructor = "AC", initial_cut_file = "cascades_300/IEEE_300_2.txt")
    
    initial_cut_branches = []
    (initial_cut_file != "none") && (initial_cut_branches = readdlm(initial_cut_file, ',', Int64))
    data = PowerModels.parse_file(file)
    buses = Dict([(parse(Int, k), v) for (k, v) in data["bus"]])
    num_buses = length(buses)
    buses = filter((i, bus) -> bus["bus_type"] != 4, buses)
    branches = Dict([(parse(Int, k), v) for (k, v) in data["branch"]])
    branches = filter((i, branch) -> branch["br_status"] == 1 && branch["f_bus"] in keys(buses) && branch["t_bus"] in keys(buses), branches)
    branch_indexes = collect(keys(branches))
    loads = Dict([(parse(Int, k), v) for (k, v) in data["load"]])
    loads = filter((i, load) -> load["status"] == 1 && load["load_bus"] in keys(buses), loads)

    log_p = Dict([(i, log(branches[i]["prob"])) for i in branch_indexes])

    totalload = 0.0
    for (i,load) in loads
        totalload += load["pd"]
    end
    # println("total load: $totalload ...")
    
    quit()
    #master_problem = Model(solver=GurobiSolver(LogToConsole=0))
    master_problem = Model(solver=CplexSolver())
    @variable(master_problem, 1e-6 <= eta <= 1e6)
    @variable(master_problem, x[i in branch_indexes], Bin)
    @variable(master_problem, p <= 0)
    @variable(master_problem, y <= 1e6)

    @constraint(master_problem, sum(x) == k)
    @constraint(master_problem, p == sum(x[i]*log_p[i] for i in branch_indexes))
    
    # adding cuts to remove some previously found solutions
    for i in 1:size(initial_cut_branches)[1]
        expr = zero(AffExpr)
        for j in initial_cut_branches[i,:]
            append!(expr, x[j])
        end
        @constraint(master_problem, expr <= k-1)
    end

    @objective(master_problem, Max, y)
    # add outer approximation of constraint y ⩽ p + log η using lazy constraint callback:  y ⩽ p + log η₀ + 1/η₀(η - η₀)
    # outer approximation of y ⩽ f(x) at x = xᵏ : y ⩽ f(xᵏ) + ∇f(xᵏ)⋅(x-xᵏ)

    function outer_approximate(cb)
        eta_val = getvalue(eta)
        p_val = getvalue(p)
        if eta_val > 0.0
            inv_eta_val = 1/eta_val
            @lazyconstraint(cb, y <= p + log(eta_val) + inv_eta_val*(eta - eta_val))
        end
    end

    addlazycallback(master_problem, outer_approximate)

    # anonymous function
    x_val = i -> getvalue(x[i])

    zlb = -1e10
    zub = 1e10
    eps = 1e-6
    
    time_taken = 0
    tic()
    solve(master_problem)

    iteration = 0
    final_xvals = Dict{Any,Any}
    final_lines = Any[]

    if (model_constructor == DCPPowerModel)
        cut_constructor = "DC"
    end

    while (zub - zlb > 0.01)
        iteration += 1
        current_xvals = Dict(i => x_val(i) for i in branch_indexes)
        current_lines = collect(keys(filter( (i, xval) -> xval > 1e-4, current_xvals)))
        p_val = getvalue(p)
        for index in current_lines
            data["branch"][string(index)]["br_status"] = 0
        end
        pm = model_constructor(data; solver = solver)
        post_pfls(pm)
        status, solve_time = solve(pm)
        for index in current_lines
            data["branch"][string(index)]["br_status"] = 1
        end
        result = PowerModels.build_solution(pm, status, solve_time)
        alpha = get_cut_coefficients(pm, cut_constructor = cut_constructor)
        sub_objective = result["objective"]
        sub_lb = p_val + log(sub_objective)
        if (sub_lb - zlb > eps)
            zlb = sub_lb
            final_xvals = current_xvals
            final_lines = current_lines
        end
        expr = zero(AffExpr)
        for i in branch_indexes
            if (current_xvals[i] > 0.9)
                append!(expr, x[i])
            end
        end
        @constraint(master_problem, expr <= k-1)
        @constraint(master_problem, eta <= sub_objective + sum(alpha[i]*x[i] for i in collect(keys(alpha))))
        solve(master_problem)
        zub = getobjectivevalue(master_problem)
        time_taken += toq()

        min_value = eps + abs(zlb)
        rel_gap = abs(zub-zlb)
        rel_gap = (min_value > eps) ? rel_gap/min_value : rel_gap
        print("ub: $zub, lb: $zlb, rel_gap: $((zub-zlb)/(eps+abs(zlb))), abs_gap: $(zub-zlb), ")
        p_val = 0.0
        for i in final_lines
            p_val += log_p[i]
        end
        print("solution: $(collect(final_lines)), ")
        log_eta = zlb - p_val
        actual_prob = exp(p_val)
        eta_val = exp(log_eta)
        print("prob: $actual_prob, ")
        print("load_shed: $eta_val, ")
        print("time_taken: $time_taken. \n")
        tic()
        
        if time_taken >= 86400
            break
        end

        if rel_gap <= 0.05 && sign(zlb)*sign(zub) > 0
            break
        end
    end

    p_val = 0.0
    for i in final_lines
        p_val += log_p[i]
    end
    println("###################################")
    println("k ... $k")
    println("solution = x* ... $(collect(final_lines))")
    println("model: $(model_constructor), cut_type: $(cut_constructor)")
    println("total number of iterations ... $iteration")
    println("solution cost = logprob(x*) + log(η(x*)) ... $zlb")
    println("probability = logprob(x*) ... $p_val")
    log_eta = zlb - p_val
    actual_prob = exp(p_val)
    eta_val = exp(log_eta)
    println("probability = prob(x*) ... $actual_prob")
    println("load shed = η* ... $eta_val")
    println("expected load shed = prob(x*)⋅η* ... $(actual_prob*eta_val)")
    time_taken += toq()
    println("time ... $time_taken")
    # solving the AC load shed model on the final set of lines
    for index in final_lines
        data["branch"][string(index)]["br_status"] = 0
    end
    pm = ACPPowerModel(data; solver = IpoptSolver(print_level=0))
    post_pfls(pm)
    status, solve_time = solve(pm)
    result = PowerModels.build_solution(pm, status, solve_time)
    println("full AC load shed ... $(result["objective"])")
    println("expected AC load shed ... $(actual_prob*result["objective"])")
    println("###################################")
    solution = Dict{AbstractString,Any}("k" => k, "lines" => collect(final_lines),
                                        "model" => model_constructor, "time" => time_taken,
                                        "cut" => cut_constructor, "prob" => actual_prob,
                                        "load_shed" => eta_val,
                                        "expected_load_shed" => actual_prob*eta_val,
                                        "ac_load_shed" => result["objective"],
                                        "expected_ac_load_shed" => actual_prob*result["objective"],
                                        "iterations" => iteration)
    push!(solution_vector, solution)

    return num_buses
end

# solution_dict = Dict{AbstractString,Any}()
solution_vector = Any[]

args = Dict{Any,Any}()
println(ARGS[1])
args["file"] = String(ARGS[1])
args["initial_nk_cut_file"] = String(ARGS[2])
args["k"] = parse(Int, ARGS[3])
args["nf"] = parse(Int, ARGS[4]) # 0 - all three, 1 - only nf, 2 - no nf, 3 - only soc (hurricane case/uniform case)
(args["initial_nk_cut_file"] == "none") && (assert(args["nf"] == 3))

if args["nf"] == 0
    num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = NFPowerModel, cut_constructor = "DC")
    num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = DCPPowerModel, cut_constructor = "DC")
    num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = SOCWRPowerModel, cut_constructor = "DC")
elseif args["nf"] == 1
    num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = NFPowerModel, cut_constructor = "DC")
elseif args["nf"] == 3
    num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = SOCWRPowerModel, cut_constructor = "DC", initial_cut_file=args["initial_nk_cut_file"])
else
    num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = DCPPowerModel, cut_constructor = "DC")
    num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = SOCWRPowerModel, cut_constructor = "DC")
end
# num_buses = master_problem(file = args["file"], k = args["k"], solver = CplexSolver(), model_constructor = SOCWRPowerModel, cut_constructor = "AC")

println(solution_vector)


#= original n-k Networks paper output-writes
if args["nf"] == 0
    f = open("./output_files/$(num_buses)_$(args["k"])", "w")
elseif args["nf"] == 1
    f = open("./output_files/$(num_buses)_$(args["k"])_nf", "w")
elseif args["nf"] == 3 # only use for probability distribution study where case hi or ui is appended to file name
    a = args["file"]
    if args["file"] != "../data/nesta_case1354_pegase_nk.m"
        case = split(split(a, "_")[length(split(a, "_"))], ".")[1]
        f = open("./output_files/$(num_buses)_$(args["k"])_soc_$(case)", "w")
    else
        f = open("./output_files/$(num_buses)_$(args["k"])_soc", "w")
    end
else
    f = open("./output_files/$(num_buses)_$(args["k"])_nonf", "w")
end

write(f, "case model k time iterations probability load_shed expected_load_shed ac_load_shed expected_ac_load_shed lines\n")
for solution in solution_vector
    if solution["model"] == PowerModels.GenericPowerModel{StandardNFForm}
        write(f, "$(num_buses) nf $(solution["k"]) $(solution["time"]) $(solution["iterations"]) $(solution["prob"]) $(solution["load_shed"]) $(solution["expected_load_shed"]) $(solution["ac_load_shed"]) $(solution["expected_ac_load_shed"]) $(solution["lines"]) \n")
    end
    if solution["model"] == PowerModels.GenericPowerModel{PowerModels.StandardDCPForm}
        write(f, "$(num_buses) dc $(solution["k"]) $(solution["time"]) $(solution["iterations"]) $(solution["prob"]) $(solution["load_shed"]) $(solution["expected_load_shed"]) $(solution["ac_load_shed"]) $(solution["expected_ac_load_shed"]) $(solution["lines"]) \n")
    end
    if solution["model"] == PowerModels.GenericPowerModel{PowerModels.SOCWRForm}
        write(f, "$(num_buses) soc $(solution["k"]) $(solution["time"]) $(solution["iterations"]) $(solution["prob"]) $(solution["load_shed"]) $(solution["expected_load_shed"]) $(solution["ac_load_shed"]) $(solution["expected_ac_load_shed"]) $(solution["lines"]) \n")
    end
end

close(f)
=# 

#= Commented out before n-k networks paper final runs
solution_dict["solution"] = solution_vector
json_string = JSON.json(solution_dict)
if endswith(args["file"], "api.m")
    write("./json_files/stoch_$(args["k"])_$(num_buses)_api.json", json_string)
elseif endswith(args["file"], "sad.m")
    write("./json_files/stoch_$(args["k"])_$(num_buses)_sad.json", json_string)
else
    write("./json_files/stoch_$(args["k"])_$(num_buses).json", json_string)
end
=#
