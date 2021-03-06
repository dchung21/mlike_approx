
param = prior

curr_part = prev_part
drops = c('leaf_id', 'psi_star', 'n_obs')


#### compute all of the resampled error ----------------------------------------

# this has stage 1 error for 2nd stage samples
resamp_error = function(part_fit) {
    psi_tilde_df = part_fit$u_df_resample %>% 
        dplyr::select(psi_tilde_1:psi_1)
    error = apply(psi_tilde_df, 2, logQ, part_fit$u_df_resample$psi_u)
    return(error)
}

psi_update = compute_weights(u_df, stage_s_part, s, psi_star)
psi_update$approx_error
psi_update$psi_tilde_df %>% head

ss_error = melt(resamp_error(stage_s_part), value.name = 'error')

approx_error = psi_update$approx_error %>% 
    dplyr::mutate(ss_error = ss_error$error) %>% 
    dplyr::mutate(tot_error = log(exp(error) + exp(ss_error)))

# create a version of u_df where each row is a re-sampled point with columns:
# (0) actual psi values for each of the points
# (1) psi values from first stage candidates  (5 candidates)
# (2) psi values from second stage candidates (5 candidates)

# input
stage_s_part$u_df_resample %>% head


psi_candidates
n_cand = 5
params = prior

### start of function here

part_id = curr_part$leaf_id        # extract partition IDs
K = length(part_id)                # number of partitions

candidate_psi = vector("list", K) # store the sub-partitions after resample
opt_psi_part  = vector("list", K) # store the sub-partitions after resample
u_df_k_list   = vector("list", K) # store resampled points w/ psi, psi_star

for (k in 1:K) {
    N_k_p = curr_part$n_obs[k] * n_samps  # num of samples to draw from A_k
    
    # set of lower/upper bounds corresponding to the k-th partition
    # (i)  omit the other three variables so that we only have ub/lb columns
    # (ii) transform row vector into a (D x 2) matrix of lb/ub
    part_k = curr_part %>%                
        dplyr::filter(leaf_id == part_id[k]) %>%
        dplyr::select(-c(leaf_id, psi_star, n_obs)) %>% 
        unlist() %>% matrix(ncol = 2, byrow = T)
    
    # sample uniformly from the D-dim partition whose lower/upper bounds
    # are defined in part_k above
    resamp_k = Matrix_runif(N_k_p, 
                            lower = part_k[,1], 
                            upper = part_k[,2]) %>% data.frame
    
    # compute psi(u) for each of the samples
    u_df_k = preprocess(resamp_k, D, params) # N_k_p x (D_u + 1)
    
    #### (1) psi values from first stage candidates  (5 candidates)
    # save candidate values for this partition by extracting from psi_candidates
    psi_cand_k = psi_candidates %>% dplyr::filter(leaf_id == part_id[k]) %>% 
        dplyr::select(-c('leaf_id'))
    # names(psi_cand_k) = paste("psi_1", 1:n_cand, sep = '_')
    # u_df_k = u_df_k %>% dplyr::mutate(psi_cand_k)
    
    # u_df_k_cand = data.frame(u_df_k, psi_cand_k)
    # u_df_k_cand %>% head
    
    # verify order is preserved
    # (u_df_k_cand$psi_u != u_df_k$psi_u) %>% sum
    
    #### (2) psi values from second stage candidates (5 candidates)
    
    #### (2a) do we even need the optimal value if we're doing candidates? I 
    ####  don't think so -- just create another candidate matrix. At this point, 
    ####  the only optimal value that we rely on the c_k_star from the PREVIOUS 
    ####  (first) stage so that we can form the candidates, i.e., 
    ####  c_k_star + (cand1, cand2, ..., cand_5)
    
    c_k_star = curr_part$psi_star[k] 
    
    # compute R(u) for each of the samples; since we're in the k-th
    # partition, we can directly subtract from psi_star[k], which we have
    # computed and stored from the previous (original) call to hml_approx()
    # this will need to be modified in the (to be)-implemented func that
    # handles fitting the residuals, rather than the func values of psi(u)
    R_df_k = u_df_k %>% dplyr::mutate(R_u = psi_u - c_k_star) %>% 
        dplyr::select(-psi_u)
    
    # fit (u, R(u)) into decision tree to obtain partition
    resid_tree = rpart(R_u ~ ., R_df_k)
    
    # extract the (data-defined) support from R_df_k
    resid_support = extractSupport(R_df_k, D)
    
    # extract partition from resid_tree
    # ntoe we omit 'psi_hat' the fitted value for the residual returned from 
    # the tree, since this value results in an underestimation of the 
    # log marginal likelihood. instead, use our own objective function to 
    # choose the optimal value of R(u) for each (sub-)partition
    resid_partition = extractPartition(resid_tree, resid_support) %>% 
        dplyr::select(-psi_hat)
    
    ####  8/9 from here, we can just compute the log volume of each of the 
    ####  hypercubes and store them separately (everything will be done 
    ####  within this function)
    # part_volume = data.frame(leaf_id = resid_partition$leaf_id,
    #                          log_vol = log_volume(resid_partition, D))
    
    # number of sub-partitions of partition k
    s_k = nrow(resid_partition) 
    
    # compute opt value (chosen by tree) for each sub-partition
    # e_kj_opt : leaf_id, Ru_choice, Ru_star, logJ_star, n_obs, lb/ub
    
    e_kj = partition_opt_update(resid_tree, R_df_k, resid_partition, D)
    # (1) obtain optimal: [leaf_id, psi_star]
    opt = e_kj$Ru_df_opt
    # (2) obtain candidates: [leaf_id, psi_1, ..., psi_5]
    cand = e_kj$Ru_df_cand
    
    #### the following calculation is superfluous since we don't go beyond 2nd stage
    #### but keep it for now since it's low-cost and easy to compute (might need
    #### it later at some point)
    # compute psi_star = c_k_star + e_kj_star, e_kj_star = Ru_star
    psi_star = cbind(leaf_id  = opt$leaf_id, 
                     psi_star = opt$Ru_star + c_k_star,
                     n_obs    = opt$n_obs)
    
    resid_partition = psi_star %>% merge(resid_partition, by = 'leaf_id')
    
    
    # store u_df_k with psi_star value so that we can compute the errors
    # u_df_k = u_df_k %>% dplyr::mutate(leaf_id = resid_tree$where)
    
    u_df_k_cand = u_df_k %>% dplyr::mutate(leaf_id = resid_tree$where)
    
    # compute psi_tilde using the candidate R(u) values
    # first column is leaf_id, throw this out so we can do element-
    # wise multiplication
    # psi_tilde is used later to compute the final approximation
    psi_tilde = cbind(leaf_id = cand$leaf_id, cand[,-1] + c_k_star)
    names(psi_tilde) = c("leaf_id", 
                         paste("psi_2_", c(1:(ncol(psi_tilde)-1)), sep = ''))
    psi_tilde = data.frame(psi_tilde, psi_cand_k)
    
    
    u_df_k_cand = merge(u_df_k_cand, psi_tilde, by = 'leaf_id')
    u_df_k_cand %>% head
    
    candidate_psi[[k]] = psi_tilde
    opt_psi_part[[k]]  = resid_partition
    u_df_k_list[[k]]   = u_df_k_cand %>% dplyr::select(-c('leaf_id')) 
}

### psi_tilde       -> used to compute final approximation using each candidate
### u_df_k_cand     -> used to compute the error + weights for each logml approx
### resid_partition -> used to compute the volume of each of the partitions

## all candidates
candidate_df = do.call(rbind, candidate_psi)

## all optimal
optimal_df = do.call(rbind, opt_psi_part)

## all of u_df_k 
u_df_resample = do.call(rbind, u_df_k_list)


## re-index the leaf IDs
K = nrow(candidate_df)
candidate_df = candidate_df %>% dplyr::mutate(leaf_id = 1:K)
optimal_df = optimal_df %>% dplyr::mutate(leaf_id = 1:K)



#### compute 2nd stage error ---------------------------------------------------
all_psi = u_df_resample %>% dplyr::select(-c(paste('u', 1:D, sep = '')))
error = apply(all_psi %>% dplyr::select(-c('psi_u')), 2, logQ, all_psi$psi_u)


#### compute 1st stage error ---------------------------------------------------

u_sub = u_df %>% dplyr::select(-psi_u)

drops   = c('leaf_id', 'psi_star', 'n_obs')

# optimal_df = part_fit$optimal_part
# candidate_df = part_fit$candidate_psi

# partitions from 2nd stage partition
part = optimal_df[,!(names(optimal_df) %in% drops)]
part_list = lapply(split(part, seq(NROW(part))), matrix_part)

# for each posterior sample, determine which partition it belongs in
part_id = apply(u_sub, 1, query_partition, part_list = part_list)

# for posterior samples that fall outside of the re-sampled partitions,
# we will use the psi_star value obtained during the previous stage
use_prev_id = which(is.na(part_id))
stage_1_psi_star = u_df_star$psi_star[use_prev_id]

# n_cand = ncol(candidate_df) - 1 # subtract off the leaf_id column
n_cand = 5 # subtract off the leaf_id column
psi_tilde_df = data.frame(matrix(0, nrow(u_df), n_cand))
names(psi_tilde_df) = names(candidate_df)[2:(n_cand+1)]
for (i in 1:n_cand) {
    # identify the psi candidate value from candidate_df
    psi_cand_i = candidate_df[,i+1]
    psi_tilde_df[,i] = psi_cand_i[part_id]
    psi_tilde_df[use_prev_id,i] = stage_1_psi_star
}


# error = apply(psi_tilde_df, 2, MAE, u_df$psi_u)
error = apply(psi_tilde_df, 2, logQ, u_df$psi_u)
approx = compute_approx(part_fit)

approx_error = data.frame(approx = approx, error = error)

u_df_star = u_df %>% 
    dplyr::mutate(leaf_id = logml_approx$u_rpart$where) %>% 
    plyr::join(prev_part %>% dplyr::select(c('leaf_id', 'psi_star')),
               by = 'leaf_id') %>% 
    dplyr::select(-c('leaf_id'))

u_df_star$psi_star[use_prev_id]

# ------------------------------------------------------------------------------










#### TODO: compute first stage errors  -----------------------------------------

u_df_resample = stage_s_part$u_df_resample
psi_tilde_df = u_df_resample %>% dplyr::select(psi_tilde_1:psi_tilde_5)

error_resample = apply(psi_tilde_df, 2, logQ, u_df_resample$psi_u)

compute_weights(u_df, stage_s_part, s, psi_star)

part_fit = stage_s_part
s = 2

u_sub = u_df %>% dplyr::select(-psi_u)

optimal_df = part_fit$optimal_part
candidate_df = part_fit$candidate_psi

part = optimal_df[,!(names(optimal_df) %in% drops)]
part_list = lapply(split(part, seq(NROW(part))), matrix_part)

# for each posterior sample, determine which partition it belongs in
part_id = apply(u_sub, 1, query_partition, part_list = part_list)

# for posterior samples that fall outside of the re-sampled partitions,
# we will use the psi_star value obtained during the previous stage
use_prev_id = which(is.na(part_id))

n_cand = ncol(candidate_df) - 1 # subtract off the leaf_id column
psi_tilde_df = data.frame(matrix(0, nrow(u_df), n_cand))
for (i in 1:n_cand) {
    # identify the psi candidate value from candidate_df
    psi_cand_i = candidate_df[,i+1]
    psi_tilde_df[,i] = psi_cand_i[part_id]
    if (stage > 1) {
        psi_tilde_df[use_prev_id,i] = psi_star[use_prev_id, stage-1]
    }
}


# error = apply(psi_tilde_df, 2, MAE, u_df$psi_u)
error = apply(psi_tilde_df, 2, logQ, u_df$psi_u)
approx = compute_approx(part_fit)

psi_star[,stage] = optimal_df$psi_star[part_id]
if (stage > 1) {
    psi_star[,stage][use_prev_id] = psi_star[use_prev_id, stage-1]
}

approx_error = data.frame(approx = approx, error = error)


