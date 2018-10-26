## Deterministic/Probabilistic N-k Interdiction for Power Systems

This repository contains the code for the paper entitled "Probabilistic N-k Failure Identification for Power Systems" ([published version](https://onlinelibrary.wiley.com/doi/abs/10.1002/net.21806) and [arxiv](https://arxiv.org/abs/1704.05391)). 

For details on the algorithm, readers are refered to either of the above versions. The code is written in the Julia Programming language using [JuMP](https://github.com/JuliaOpt/JuMP.jl) and [PowerModels](https://github.com/lanl-ansi/PowerModels.jl). 

## Citing the work

If you find the code useful in your work, we kindly request that you cite the following two publications: [1](https://onlinelibrary.wiley.com/doi/abs/10.1002/net.21806) and [2](https://ieeexplore.ieee.org/document/8442948/) 
```
@article{sundar2018probabilistic,
  title={Probabilistic N-k failure-identification for power systems},
  author={Sundar, Kaarthik and Coffrin, Carleton and Nagarajan, Harsha and Bent, Russell},
  journal={Networks},
  volume={71},
  number={3},
  pages={302--321},
  year={2018},
  publisher={Wiley Online Library},
  doi={10.1002/net.21806}
}

@inproceedings{powermodels, 
  author = {Carleton Coffrin and Russell Bent and Kaarthik Sundar and Yeesian Ng and Miles Lubin}, 
  title = {PowerModels.jl: An Open-Source Framework for Exploring Power Flow Formulations}, 
  booktitle = {2018 Power Systems Computation Conference (PSCC)}, 
  year = {2018},
  month = {June},
  pages = {1-8}, 
  doi = {10.23919/PSCC.2018.8442948}
}
```

## License

This code is provided under a BSD license as part of the Multi-Infrastructure Control and Optimization Toolkit (MICOT) project, LA-CC-13-108.


