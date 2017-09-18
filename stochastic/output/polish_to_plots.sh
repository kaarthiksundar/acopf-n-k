#!/bin/bash

echo "relative gap vs iteration data for the polish instances for k in (2,10)";
i=6;
echo $(grep -w rel_gap stoch_case2383_${i}.out | cut -d " " -f 6 | cut -d "," -f 1 | awk '{ printf "%0.2f,", $1*100}');
