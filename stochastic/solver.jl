function solve(p::Problem, c::Configuration, t::Table)

    termination_flag = 0
    time = 0.0
    while get_opt_gap(p) > get_opt_gap(c)

        # solve outer problem and update Problem struct
        if get_iteration_count(p) == 0 && length(get_current_solution(p)) == c.k
            set_upper_bound(p, 1e4)
        else
            cplex_optimizer = with_optimizer(CPLEX.Optimizer)
            MOI.set(p.model, MOI.RawParameter("CPX_PARAM_SCRIND"), 0)
            time = @elapsed JuMP.optimize!(p.model, cplex_optimizer)
            @show JuMP.termination_status(p.model) == MOI.OPTIMAL
            (JuMP.termination_status(p.model) == MOI.INFEASIBLE) && (print_table_footer(t); termination_flag = 1; break)
            set_upper_bound(p, JuMP.objective_value(p.model))
            set_current_solution(p)
            @assert length(get_current_solution(p)) == c.k
        end

        # create inner problem using interdiction plan 
        time_inner, status, inner_model = solve_inner_problem(p, c, JuMP.Model())
        time += time_inner

        solution_dict = get_inner_solution(p, inner_model)
        add_cutting_plane(p, solution_dict)
        add_no_good_cut(p, c)

        # iteration count 
        increment_iteration_count(p)
        # (get_iteration_count(p)%1 == 0) && (update_dual_bounds(p, c))


        # print log 
        update_table(p, t, time)
        set_computation_time(p, t)
        print_table_line(t, c)
    end 

    (termination_flag == 0) && (print_table_footer(t))
    return 
end
