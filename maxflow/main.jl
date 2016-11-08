using JuMP
using Distributions
using CPLEX
using PowerModels

function run_max_flow(; file = "../data/nesta_case24_ieee_rts.m", k = 4)

    data = PowerModels.parse_file(file)
    data, sets = PowerModels.process_raw_data(data)
    buses = [ Int(bus["index"]) => bus for bus in data["bus"] ]
    buses = filter((i, bus) -> bus["bus_type"] != 4, buses)
    branches = [ Int(branch["index"]) => branch for branch in data["branch"] ]
    branches = filter((i, branch) -> branch["br_status"] == 1 && branch["f_bus"] in keys(buses) && branch["t_bus"] in keys(buses), branches)
    branch_indexes = collect(keys(branches))
    bus_indexes = collect(keys(buses))
    


end

run_max_flow(file = "../data/nesta_case118_ieee.m", k = 10)
