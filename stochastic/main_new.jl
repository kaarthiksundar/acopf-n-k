using JuMP
using PowerModels
using CPLEX
using Gurobi
using MathOptInterface
using Memento

const PMs = PowerModels
const MOI = MathOptInterface

Memento.setlevel!(getlogger("PowerModels"), "error")
logger = Memento.config!("info")

include("parse.jl")
include("utils.jl")
include("models.jl")
include("solver.jl")

# reading command line arguments
configuration = Configuration(parse_commandline())
print_configuration(configuration)
(configuration.debug) && (Memento.setlevel!(logger, "debug"))

# setting up problem data structure
problem = Problem(PMs.parse_file(get_case(configuration)))
print_total_load(problem)

# create and solve model
populate_model(problem, configuration)
table = Table() 
print_table_header(table) 
solve(problem, configuration, table)

# write_result(problem, configuration)


