#!/bin/bash

echo "k pr ls weighted_ls"
for k in `seq 2 10`;
do
    cat 14_${k} | grep dc | cut -d " " -f 3,6,7,8,11 
done
