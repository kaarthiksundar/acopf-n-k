using PowerModels
using JuMP
using CPLEX
include("prob.jl")

function get_independent_load_shed(; file = "../data/nesta_case24_ieee_rts.m", solver = IpoptSolver(), model_constructor = SOCWRPowerModel, lines = final_lines)

    independent_load_shed = [i => 0.0 for i in lines]
    for line in lines
        data = PowerModels.parse_file(file)
        for branch in data["branch"]
            if Int(branch["index"]) == line
                branch["br_status"] = 0
            end
        end
        buses = [ Int(bus["index"]) => bus for bus in data["bus"] ]
        buses = filter((i, bus) -> bus["bus_type"] != 4, buses)
        branches = [ Int(branch["index"]) => branch for branch in data["branch"] ]
        branches = filter((i, branch) -> branch["br_status"] == 1 && branch["f_bus"] in keys(buses) && branch["t_bus"] in keys(buses), branches)
        branch_indexes = collect(keys(branches))
        pm = model_constructor(data; solver = solver)
        post_pfls(pm)
        status, solve_time = solve(pm)
        result = PowerModels.build_solution(pm, status, solve_time)
        independent_load_shed[line] = result["objective"]
    end
    return independent_load_shed;
end
