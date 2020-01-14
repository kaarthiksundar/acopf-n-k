mutable struct Configuration
    config::Dict{Any,Any}
    case_filename::AbstractString
    case_path::AbstractString
    case_file::AbstractString
    problem_type::Symbol
    time_limit::Int
    opt_gap::Float64
    k::Int 
    debug::Bool
    
    function Configuration(config)
        c = new()
        c.config = config 
        c.case_filename = config["file"]
        c.case_path = config["path"]
        c.case_file = c.case_path * c.case_filename
        c.problem_type = config["problem_type"]
        c.time_limit = config["timeout"]
        c.opt_gap = config["gap"]
        c.k = config["k"]
        c.debug = config["debug"]
        return c
    end

end 

get_case(c::Configuration) = c.case_file 
get_problem_type(c::Configuration) = c.problem_type 
get_time_limit(c::Configuration) = c.time_limit
get_opt_gap(c::Configuration) = c.opt_gap
get_k(c::Configuration) = c.k 

function print_configuration(c::Configuration)
    print("CLI arguments\n")
    println("Case           :  $(get_case(c))")
    println("Problem type   :  $(get_problem_type(c))")
    println("k value        :  $(get_k(c))")
    println("Time limit     :  $(get_time_limit(c))")
    println("Optimality gap :  $(get_opt_gap(c)*100)%")
    println("")
    return
end 

mutable struct Problem 
    data::Dict{String,Any}
    ref::Dict{Any,Any}
    total_load::Float64
    model::JuMP.Model 
    best_solution::Vector{Int}
    current_solution::Vector{Int}
    upper_bound::Float64
    best_incumbent::Float64
    current_incumbent::Float64
    opt_gap::Float64
    iterations::Int
    computation_time::Float64
    
    function Problem(data)
        @assert !haskey(data, "multinetwork")
        @assert !haskey(data, "conductors")
        p = new()
        p.data = data
        p.ref = PMs.build_ref(data)[:nw][0]
        p.total_load = sum([abs(load["pd"]) for (i, load) in p.ref[:load]]) 
        p.model = Model()
        p.best_solution = Vector{Int}()
        p.current_solution = Vector{Int}()
        p.upper_bound = Inf
        p.best_incumbent = -Inf
        p.current_incumbent = -Inf
        p.opt_gap = Inf
        p.iterations = 0
        p.computation_time = 0.0
        return p
    end 
end

get_data(p::Problem) = p.data
get_ref(p::Problem) = p.ref 
get_total_load(p::Problem) = p.total_load
get_model(p::Problem) = p.model 
get_best_solution(p::Problem) = p.best_solution 
get_current_solution(p::Problem) = p.current_solution
get_upper_bound(p::Problem) = p.upper_bound 
get_best_incumbent(p::Problem) = p.best_incumbent
get_current_incumbent(p::Problem) = p.current_incumbent
get_opt_gap(p::Problem) = p.opt_gap 
get_iteration_count(p::Problem) = p.iterations
get_computation_time(p::Problem) = p.computation_time

function print_total_load(p::Problem)
    println("Total load     :  $(round(get_total_load(p); digits=2))")
    println("")
    return
end 

function set_dual_bounds(p::Problem, dual_bounds::Dict)
    p.dual_bounds = dual_bounds
    return 
end

mutable struct Table
    fields::Dict{Symbol,Any}
    field_chars::Dict{Symbol,Any}
    all_fields::Vector{Symbol}
    total_field_chars::Int

    function Table()
        t = new()
        t.fields = Dict{Symbol,Any}()
        t.field_chars = Dict{Symbol,Any}()
        t.fields[:Incumbent] = NaN 
        t.fields[:BestBound] = NaN
        t.fields[:Gap] = NaN 
        t.fields[:Time] = 0.0
        t.fields[:Iter] = 0
        t.field_chars[:Incumbent] = 28
        t.field_chars[:BestBound] = 28
        t.field_chars[:Gap] = 12
        t.field_chars[:Time] = 12
        t.field_chars[:Iter] = 12
        t.all_fields = [:Iter, :Incumbent, :BestBound, :Gap, :Time]
        t.total_field_chars = 28*2 + 12*3
        return t
    end 
end 

function set_computation_time(p::Problem, t::Table)
    p.computation_time = t.fields[:Time]
    return 
end 

function update_table(p::Problem, t::Table, time::Float64)
    t.fields[:Incumbent] = get_best_incumbent(p)
    t.fields[:BestBound] = get_upper_bound(p)
    t.fields[:Gap] = get_opt_gap(p)
    t.fields[:Time] += time 
    t.fields[:Iter] = get_iteration_count(p)
    return 
end

function print_table_header(t::Table)
    println("")
    println(repeat("-", t.total_field_chars))
    println(get_table_header(t))
    println(repeat("-", t.total_field_chars))
    return 
end

function print_table_line(t::Table, c::Configuration) 
    println(get_table_line(t, c))
    return 
end 

function print_table_footer(t::Table)
    println(repeat("-", t.total_field_chars))
    return 
end

function get_table_header(t::Table)
    line = ""
    for f in t.all_fields
        name = (f == :BestBound) ? "Best Bound" : string(f)
        (f == :Gap) && (name = "Gap (%)")
        padding = t.field_chars[f] - length(name)
        line *= repeat(" ", trunc(Int, floor(padding/2)))
        line *= name 
        line *= repeat(" ", trunc(Int, ceil(padding/2)))
    end 
    return line
end 

function get_table_line(t::Table, c::Configuration)
    line = ""
    for f in t.all_fields
        if f == :Iter 
            value = string(t.fields[f]) 
            padding = t.field_chars[f] - length(value)
            line *= repeat(" ", trunc(Int, floor(padding/2)))
            line *= value
            line *= repeat(" ", trunc(Int, ceil(padding/2)))
        end 

        if f == :Incumbent || f == :BestBound
            value = isinf(t.fields[f]) ? "-" : string(round(t.fields[f]; digits=2))
            padding = t.field_chars[f] - length(value)
            line *= repeat(" ", trunc(Int, floor(padding/2)))
            line *= value
            line *= repeat(" ", trunc(Int, ceil(padding/2)))
        end 

        if f == :Gap
            value = ""
            if isnan(t.fields[f])
                value = "-"
            elseif  isinf(t.fields[f])
                value = "∞"
            else
                value = round(t.fields[f]*100; digits=1)
                if length(string(value)) < t.field_chars[f]
                    if value < get_opt_gap(c)*100
                        value = "opt"
                    elseif value > 1000
                        value = "∞"
                    else
                        value = string(value)
                    end
                else
                    value = string(value)
                end
            end
            padding = t.field_chars[f] - length(value)
            line *= repeat(" ", trunc(Int, floor(padding/2)))
            line *= value
            line *= repeat(" ", trunc(Int, ceil(padding/2)))
        end 

        if f == :Time 
            value = string(round(t.fields[f]; digits=1))
            padding = t.field_chars[f] - length(value)
            line *= repeat(" ", trunc(Int, floor(padding/2)))
            line *= value
            line *= repeat(" ", trunc(Int, ceil(padding/2)))
        end 
    end 

    return line 
end 