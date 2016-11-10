using PGFPlots
import JSON

case = ARGS[1]
case_kind = ARGS[2]
string_split = split(case, "_")
case_number = parse(Int, string_split[1])
case_type = string_split[2]

k_max = 0
if case_number == 24
    if case_kind == "det"
        k_max = 38
    else
        k_max = 20
    end
else
    if case_kind == "det"
        k_max = 120
    else
        k_max = 20
    end
end 

k_values = collect(2:k_max)

dc_load_shed = zeros(length(k_values))
dc_times = zeros(length(k_values))
dc_iterations = zeros(length(k_values))
dc_ac_load_shed = zeros(length(k_values))

soc1_load_shed = zeros(length(k_values))
soc1_times = zeros(length(k_values))
soc1_iterations = zeros(length(k_values))
soc1_ac_load_shed = zeros(length(k_values))

soc2_load_shed = zeros(length(k_values))
soc2_times = zeros(length(k_values))
soc2_iterations = zeros(length(k_values))
soc2_ac_load_shed = zeros(length(k_values))

for k in 2:k_max
    if case_type == "normal"
        file = string(case_kind, "_", k, "_", case_number, ".json")
    else
        file = string(case_kind, "_", k, "_", case_number, "_", case_type, ".json")
    end 
    solution = JSON.parsefile(file)["solution"]
    dc_load_shed[k-1] = solution[1]["load_shed"]
    dc_ac_load_shed[k-1] = (typeof(solution[1]["ac_load_shed"]) == Void) ? dc_load_shed[k-1] : solution[1]["ac_load_shed"]
    dc_times[k-1] = solution[1]["time"]
    dc_iterations[k-1] = solution[1]["iterations"]

    soc1_load_shed[k-1] = solution[2]["load_shed"]
    soc1_ac_load_shed[k-1] = (typeof(solution[2]["ac_load_shed"]) == Void) ? soc1_load_shed[k-1] : solution[2]["ac_load_shed"]
    soc1_times[k-1] = solution[2]["time"]
    soc1_iterations[k-1] = solution[1]["iterations"]
    
    soc2_load_shed[k-1] = solution[3]["load_shed"]
    soc2_ac_load_shed[k-1] = (typeof(solution[3]["ac_load_shed"]) == Void) ? soc2_load_shed[k-1] : solution[3]["ac_load_shed"]
    soc2_times[k-1] = solution[3]["time"]
    soc2_iterations[k-1] = solution[3]["iterations"]
end 

plt = Axis([
            Plots.Linear(k_values, dc_load_shed, markSize=0.5, legendentry=L"DC"),
            Plots.Linear(k_values, soc1_load_shed, markSize=0.5, legendentry=L"SOC"),
            Plots.Linear(k_values, dc_ac_load_shed, markSize=0.5, legendentry=L"DC(AC)"),
            Plots.Linear(k_values, soc1_ac_load_shed, markSize=0.5, legendentry=L"SOC(AC)"),
            #Plots.Linear(k_values, soc2_load_shed, markSize=0.5, legendentry=L"soc-ac") 
           ], 
           xlabel="k value", title="objective values", xmin=0, xmax=k_values[length(k_values)]+1, legendPos="south east")

save("objective_$(case_number)_$(case_type)_$(case_kind).pdf", plt)

plt = Axis([
            Plots.Linear(k_values, dc_iterations, markSize=0.5, legendentry=L"DC"),
            Plots.Linear(k_values, soc1_iterations, markSize=0.5, legendentry=L"SOC"),
            #Plots.Linear(k_values, soc2_iterations, markSize=0.5, legendentry=L"soc-ac") 
           ], 
           xlabel="k value", title="iteration count", xmin=0, xmax=k_values[length(k_values)]+1, legendPos="north east")

save("iteration_$(case_number)_$(case_type)_$(case_kind).pdf", plt)

plt = Axis([
            Plots.Linear(k_values, dc_times, markSize=0.5, legendentry=L"DC"),
            Plots.Linear(k_values, soc1_times, markSize=0.5, legendentry=L"SOC"),
            #Plots.Linear(k_values, soc2_times, markSize=0.5, legendentry=L"soc-ac") 
           ], 
           xlabel="k value", title="time taken (seconds)", xmin=0, xmax=k_values[length(k_values)]+1, legendPos="north east")

save("time_$(case_number)_$(case_type)_$(case_kind).pdf", plt)


