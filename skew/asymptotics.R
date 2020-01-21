
# ------------------------------------------------------------------------------


library(mvtnorm)           # for draws from multivariate normal
library("numDeriv")        # for grad() function - numerical differentiation
library('MCMCpack')        # for rinvgamma() function
library(sn)
library(VGAM)

DELL_PATH = "C:/Users/chuu/mlike_approx"
# LEN_PATH  = "C:/Users/ericc/mlike_approx"
# path for lenovo
# setwd(LEN_PATH)

# path for dell
setwd(DELL_PATH)

source("partition/partition.R")         # load partition extraction functions
source("hybrid_approx.R")               # load main algorithm functions
source("skew/mv_skew_normal_helper.R")  # load psi(), lambda()



# fixed settings ---------------------------------------------------------------
D = 4
alpha = rep(1, D) 
mu_0 = rep(0, D)
Omega = diag(1, D)

# Sigma = D / N * Omega 
# Sigma_inv = solve(Sigma)

N_vec_log = seq(6, 13, 0.02)        # sample size that is uniform over log scale
N_vec     = floor(exp(N_vec_log))   # sample size to use to generate data
logZ_0    = numeric(length(N_vec))
logZ      = numeric(length(N_vec))
logZ_med  = numeric(length(N_vec))

print(length(N_vec))


for (i in 1:length(N_vec)) {
    
    N = N_vec[i]
    Sigma = D / N * Omega 
    Sigma_inv = solve(Sigma)
    
    logZ_0[i] = D / 2 * log(2 * pi) + 0.5 * log_det(Sigma) + log(0.5)
    
    print(paste("iter = ", i, 
                "/", length(N_vec), 
                " -- Calculating LIL for D = ", D, ", N = ", N, sep = ''))
    
    J = 1e4
    N_approx = 100
    u_samps = rmsn(J, xi = mu_0, Omega = Sigma, alpha = alpha) %>% data.frame 
    u_df_full = preprocess(u_samps, D)
    approx_skew = approx_lil(N_approx, D, u_df_full, J/N_approx)
    
    logZ[i] = mean(approx_skew)
    logZ_med[i] = median(approx_skew)
}


# true LIL ---------------------------------------------------------------------
lil_df = data.frame(logZ_0 = logZ_0, logn = log(N_vec))

formula1 = y ~ x
ggplot(lil_df, aes(logn, logZ_0)) + geom_point() + 
    labs(title = "") + 
    geom_smooth(method = lm, se = T, formula = formula1) +
    stat_poly_eq(aes(label = paste(..eq.label.., sep = "~~~")), 
                 label.x.npc = "right", label.y.npc = "top",
                 eq.with.lhs = "logZ_0~`=`~",
                 eq.x.rhs = "~logN",
                 formula = formula1, parse = TRUE, size = 8) +
    theme_bw(base_size = 16)



# approx LIL -------------------------------------------------------------------

lil_df = data.frame(logZ = logZ, logn = log(N_vec))
lil_df = data.frame(logZ = logZ_med, logn = log(N_vec))


lil_df_finite = lil_df[is.finite(lil_df$logZ),]

lil_df_finite %>% dim

formula1 = y ~ x
ggplot(lil_df, aes(logn, logZ)) + geom_point() + 
    labs(title = "") + 
    geom_smooth(method = lm, se = T, formula = formula1) +
    stat_poly_eq(aes(label = paste(..eq.label.., sep = "~~~")), 
                 label.x.npc = "right", label.y.npc = "top",
                 eq.with.lhs = "logZ~`=`~",
                 eq.x.rhs = "~logN",
                 formula = formula1, parse = TRUE, size = 8) +
    theme_bw(base_size = 16)


# overlays ---------------------------------------------------------------------

lil_df = data.frame(logZ_0 = logZ_0, logZ = logZ, logZ_med = logZ_med, 
                    logn = log(N_vec))

lil_df = data.frame(logZ_0 = logZ_0, logZ = logZ, 
                    logn = log(N_vec))

lil_df = lil_df[is.finite(lil_df$logZ),]

lil_df_long = melt(lil_df, id.vars = "logn")

ggplot(lil_df_long, aes(x = logn, y = value, 
                        color = as.factor(variable))) + geom_point() + 
    geom_smooth(method = lm, se = F, formula = formula1) +
    stat_poly_eq(aes(label = paste(..eq.label.., sep = "~~~")), 
                 label.x.npc = "right", label.y.npc = "top",
                 eq.with.lhs = "logZ~`=`~",
                 eq.x.rhs = "~logN",
                 formula = formula1, parse = TRUE, size = 8) +
    theme_bw(base_size = 16) + 
    theme(legend.position = "none")










