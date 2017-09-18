#!/bin/bash

for i in `seq 1 3`
do
    for k in `seq 2 15`;
    do
        cat 240_${k}_soc_f${i} | grep soc | cut -f 7,8 -d " "
    done
    echo
done 

echo



