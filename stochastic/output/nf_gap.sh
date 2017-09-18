#!/bin/bash

for k in `seq 6 10`;
do
    cat stoch_case118_nf_$k.out | grep lb: | tail -1 | cut -f 1 -d "," | cut -f 2 -d " " | sed 's/-//g'
done

echo

for k in `seq 6 10`;
do
    cat stoch_case118_nf_$k.out | grep lb: | tail -1 | cut -f 2 -d "," | cut -f 3 -d " " | sed 's/-//g'
done
