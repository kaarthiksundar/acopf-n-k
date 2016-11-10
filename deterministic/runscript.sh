#!/bin/bash
#
#SBATCH --ntasks=1
#SBATCH --constraint=haswell
#SBATCH --time=72:00:00

srun julia main.jl $1 $2
