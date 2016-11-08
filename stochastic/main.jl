using JuMP
using Ipopt
using CPLEX
using Gurobi
using PowerModels
using Distributions
include("prob.jl")
include("cut.jl")
include("io.jl")

function master_problem(; file = "../data/nesta_case24_ieee_rts.m", k = 4, solver = IpoptSolver(), model_constructor = SOCWRPowerModel, cut_constructor = "AC")

    data = PowerModels.parse_file(file)
    parse_prob_file(file, data)
    buses = [ Int(bus["index"]) => bus for bus in data["bus"] ]
    buses = filter((i, bus) -> bus["bus_type"] != 4, buses)
    branches = [ Int(branch["index"]) => branch for branch in data["branch"] ]
    branches = filter((i, branch) -> branch["br_status"] == 1 && branch["f_bus"] in keys(buses) && branch["t_bus"] in keys(buses), branches)
    branch_indexes = collect(keys(branches))

    #=
    srand(2016)
    d = Uniform()
    =#
    branch_probabilities = [ i => branches[i]["prob"] for i in branch_indexes ]
    log_p = [ i => log(branch_probabilities[i]) for i in branch_indexes ]
    
    totalload = 0.0
    for (i,bus) in buses
        totalload += bus["pd"]
    end
    # println("total load: $totalload ...")

    master_problem = Model(solver=GurobiSolver(LogToConsole=0))
    @variable(master_problem, 1e-6 <= eta <= 1e6)
    @variable(master_problem, x[i in branch_indexes], Bin)
    @variable(master_problem, p <= 0)
    @variable(master_problem, y <= 1e6)

    @constraint(master_problem, sum(x) == k)
    @constraint(master_problem, p == sum{ x[i]*log_p[i], i in branch_indexes})

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

    solve(master_problem)

    iteration = 0
    final_xvals = Dict{Any,Any}
    final_lines = Any[]

    if (model_constructor == DCPPowerModel)
        cut_constructor = "DC"
    end

    while (abs(zub - zlb) > 0.01*max(abs(zlb),(zub)))
        iteration += 1
        current_xvals = [ i => x_val(i) for i in branch_indexes]
        current_lines = collect(keys(filter( (i, xval) -> xval > 1e-4, current_xvals)))
        p_val = getvalue(p)
        data = PowerModels.parse_file(file)
        for branch in data["branch"]
            for index in current_lines
                if Int(branch["index"]) == index
                    branch["br_status"] = 0
                end
            end
        end
        pm = model_constructor(data; solver = solver)
        post_pfls(pm)
        status, solve_time = solve(pm)
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
    
    p_val = getvalue(p)
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
    println("###################################")


end

# model_constructor = DCPPowerModel; cut_constructor = "DC"/"AC"
for k in [30]
    master_problem(file = "../data/nesta_case73_ieee_rts.m", k = k, solver = IpoptSolver(print_level=0), model_constructor = SOCWRPowerModel, cut_constructor = "DC")
end 
