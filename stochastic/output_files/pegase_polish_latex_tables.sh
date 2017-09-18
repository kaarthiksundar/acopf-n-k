#!/bin/bash

# the round function:
round()
{
    echo $(printf %.$2f $(echo "scale=$2;(((10^$2)*$1)+0.5)/(10^$2)" | bc))
};

#for i in `seq 2 8`
#do
#    echo $(grep soc 1354_${i}_soc | cut -f 4 -d " ")/3600 | bc -l
#done

echo "pegase/polish results : k time iter sol gap ac time iter sol gap ac"

for i in `seq 2 10`
do 
    iter_pegase=$(cat 1354_${i}_soc | grep -w soc | cut -d " " -f 5) 
    feas_pegase=$(cat 1354_${i}_soc | grep -w soc | cut -d " " -f 8) 
    ac_pegase=$(cat 1354_${i}_soc | grep -w soc | cut -d " " -f 10)
    line_output_pegase=$(cat ../output/stoch_case1354_${i}.out | grep -w rel_gap | tail -1)
    rel_gap_pegase=$(cat ../output/stoch_case1354_${i}.out | grep -w rel_gap | tail -1 | cut -d " " -f 6 | cut -d "," -f 1)
    time_pegase=$(cat ../output/stoch_case1354_${i}.out | grep -w rel_gap | tail -1 | cut -d " " -f 16)
    
    iter_polish=$(cat 2383_${i}_soc_nk | grep -w soc | cut -d " " -f 5) 
    feas_polish=$(cat 2383_${i}_soc_nk | grep -w soc | cut -d " " -f 8) 
    ac_polish=$(cat 2383_${i}_soc_nk | grep -w soc | cut -d " " -f 10)
    line_output_polish=$(cat ../output/stoch_case2383_${i}.out | grep -w rel_gap | tail -1)
    rel_gap_polish=$(cat ../output/stoch_case2383_${i}.out | grep -w rel_gap | tail -1 | cut -d " " -f 6 | cut -d "," -f 1);
    if [ $(echo " $rel_gap_polish > 1.0" | bc) -eq 1 ]; then
        rel_gap_polish=$(cat ../output/stoch_case2383_${i}.out | grep -w rel_gap | tail -1 | cut -d " " -f 8 | cut -d "," -f 1);
    fi
    time_polish=$(cat ../output/stoch_case2383_${i}.out | grep -w rel_gap | tail -1 | cut -d " " -f 16)

    echo $i "&" $(round $(echo ${time_pegase::-1}) 2) "&" $iter_pegase "&" $(round $feas_pegase*100 2) "&" $(round $rel_gap_pegase*100 2) "&" $(round $ac_pegase*100 2) "&" $(round $(echo ${time_polish::-1}) 2) "&" $iter_polish "&" $(round $feas_polish*100 2) "&" $(round $rel_gap_polish*100 2) "&" $(round $ac_polish*100 2) "\\\\"
done
