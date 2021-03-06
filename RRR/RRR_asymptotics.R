

library(dplyr)
library(mvtnorm)


# path for lenovo
LEN_PATH  = "C:/Users/ericc/mlike_approx"
setwd(LEN_PATH)

# files must be loaded in this order, since *_helper.R file will sometimes
# overwrite a function defined in hybrid_approx.R depending on the example

source("partition/partition.R")         # load partition extraction functions
source("hybrid_approx_v1.R")            # load main algorithm functions
source("RRR/RRR_helper.R")              # load psi(), lambda(), preprocess()
source("RRR/gibbs_RRR.R")              # load psi(), lambda(), preprocess()
source("hybrid_const.R")
source('extractPartition.R')            # load extractPartition() function
options(scipen = 999)


## testing refactored code
source("C:/Users/ericc/Dropbox/logML/load_libraries.R")
source("C:/Users/ericc/Dropbox/logML/algo_helpers.R")
source("C:/Users/ericc/Dropbox/logML/partition.R")
source("C:/Users/ericc/Dropbox/logML/logML_approx.R")

LEN_PATH  = "C:/Users/ericc/mlike_approx"
setwd(LEN_PATH)
source("RRR/RRR_helper.R")              # load psi(), lambda(), preprocess()
source("RRR/gibbs_RRR.R")               # load sampleRRR()


p = 3             # number of columns in X
q = 5             # number of columns in Y

# p = 8             # number of columns in X
# q = 6             # number of columns in Y

r_0 = 2           # true rank
r = 2             # model-postulated rank
D = r * p + q * r # dimension of each MCMC sample
sig2 = 1          # fixed for now.
del = 10^(-2)     # prior parameter -- one of these is squared version ?



set.seed(1)
A_0 = matrix(rnorm(p * r_0, 0, 1), p, r_0) # (p x r) matrix
B_0 = matrix(rnorm(q * r_0, 0, 1), q, r_0) # (q x r) matrix


# testing ----------------------------------------------------------------------

u = u_samps[300,] %>%  unname %>% unlist

matrix(u[1:(p * r)], p, r)
matrix(u[(p * r + 1):D], r, q)



# testing ----------------------------------------------------------------------


# replace this with J later
nMCMC = 300       # number of MCMC samples from the posterior AFTER burnin
nBurn = 500       # number of samples to discard


K_sims    = 100                                # num of sims to run for each N
N_vec_log = seq(5, 12, by = 0.25)              # sample size grid unif in log
N_vec     = floor(exp(N_vec_log)) %>% unique   # sample size to generate data
LIL_N_k_hat = matrix(0, length(N_vec), K_sims) 

i = 4; k = 1;


for (i in 1:length(N_vec)) {
    
    N = N_vec[i]

    for (k in 1:K_sims) {
        
        set.seed(1)
        # generate data, sample from posterior ---------------------------------
        gibbs_obj = sampleRRR(nMCMC, nBurn, A_0, B_0, p, q, r_0, r, D, N, sig2, del)
        
        param_list = list(p = p, q = q, r = r, n = N, d = D,  # dimensions vars
                          Y = gibbs_obj$Y, X = gibbs_obj$X,   # response, design
                          XtX = gibbs_obj$XtX, Xty = gibbs_obj$Xty,
                          sig2 = sig2, del = del)             # prior params
        
        # compute log-likelihood evaluated at max
        loglik_max = loglik_true(A_0, B_0, param_list)
        
        # extract posterior samples from gibbs object
        u_samps = gibbs_obj$u_samps
        
        # evaluate psi(u) for each of the posterior samples
        u_df = preprocess(u_samps, D, param_list) # nMCMC x (d + 1) 
        
        # generate hybrid approximation
        hml_approx = hml(1, D, u_df, nMCMC, param_list)
        
        # hml_approx$verbose_partition
        # hml_approx$partition
        # u_df_star = hml_approx$u_df_star
        hml_approx$const_vec  # -2366.219
        hml_approx$hybrid_vec # -2366.219
        hml_approx$taylor_vec # -2212.549
        
        # test hml_const() function
        hml_approx_const = hml_const(1, D, u_df, nMCMC, param_list)   # should equal below
        # hml_approx_const$n_partitions
        # hml_approx_const$const_approx
        # hml_approx_const$param_out
        # log_sum_exp(hml_approx_const$const_approx)
        # u_df_star = hml_approx_const$u_df_fit
        
        hml_approx_const$const_vec # -2366.219
        
        # TODO: integral over each of the partitions
        
        
        # subtract maximized likelihood from the resulting approximation
        LIL_N_k_hat[i, k] = hml_approx$hybrid_vec - loglik_max # -147.6771
        
    } # end inner loop over K_sims
    
    print(paste("iter ", i, "/", length(N_vec), ": ",
                "approx LIL for N = ", N, " -- LIL = ",
                round(mean(LIL_N_k_hat[i, ]), 2), sep = ''))
    
} # end outer loop over sample size


lil_hyb   = rowMeans(LIL_N_k_hat)  # length(N_vec) x 1


log_N     = log(N_vec)             # length(N_vec) x 1
log_log_N = log(log_N)

LIL_df = data.frame(LIL_hat = lil_hyb, log_N = log(N_vec), log_log_N = log_log_N)

lm(LIL_hat ~ ., LIL_df)

library(reshape2)
library(ggpmisc)
formula1 = y ~ x


ggplot(LIL_df[-c(1:7),], aes(x = log_N, y = LIL_hat)) + geom_point(size = 1.3) + 
    geom_smooth(method = lm, se = F, formula = formula1) +
    labs(x = "log(n)", y = "log(Z)", 
         title = "Hybrid (Blue)") + 
    stat_poly_eq(aes(label = paste(..eq.label.., sep = "~~~")), 
                 label.x.npc = "right", label.y.npc = "top",
                 eq.with.lhs = "logZ~`=`~",
                 eq.x.rhs = "~logN",
                 formula = formula1, parse = TRUE, size = 8)


ggplot(LIL_df, aes(x = log_N, y = LIL_hat)) + geom_point(size = 1.3) + 
    geom_smooth(method = lm, se = F, formula = formula1) +
    labs(x = "log(n)", y = "log(Z)", 
         title = "Hybrid (Blue)") + 
    stat_poly_eq(aes(label = paste(..eq.label.., sep = "~~~")), 
                 label.x.npc = "right", label.y.npc = "top",
                 eq.with.lhs = "logZ~`=`~",
                 eq.x.rhs = "~logN",
                 formula = formula1, parse = TRUE, size = 8) +
    scale_y_continuous(limits = c(-550, -200)) + 
    theme_bw(base_size = 16) + 
    theme(legend.position = "none")





















