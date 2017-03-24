#!/bin/bash
#
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --time=72:00:00


srun julia main.jl $1 $2 $3
