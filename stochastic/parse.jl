using ArgParse

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--file", "-f"
        help = "case file name"
        arg_type = String 
        default = "nesta_case24_ieee_rts_nk.m"

        "--path", "-p"
        help = "data directory path"
        arg_type = String
        default = "../data/"

        "--problem_type"
        help = "[:nf, :dc, :soc]"
        arg_type = Symbol 
        default = :nf

        "--timeout", "-t"
        help = "time limit for the run in seconds"
        arg_type = Int 
        default = 86400

        "--gap", "-g"
        help = "absolute optimality gap"
        arg_type = Float64
        default = 1e-2

        "-k" 
        help = "k value for interdiction"
        arg_type = Int 
        default = 2

        "--debug"
        help = "debug flag"
        action = :store_true
    end 

    return parse_args(s)
end