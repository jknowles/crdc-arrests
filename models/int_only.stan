// generated with brms 2.22.0
functions {
  /* integer sequence of values
   * Args:
   *   start: starting integer
   *   end: ending integer
   * Returns:
   *   an integer sequence from start to end
   */
  array[] int sequence(int start, int end) {
    array[end - start + 1] int seq;
    for (n in 1:num_elements(seq)) {
      seq[n] = n + start - 1;
    }
    return seq;
  }
  // compute partial sums of the log-likelihood
  real partial_log_lik_lpmf(array[] int seq, int start, int end, data array[] int Y, data array[] int trials, real Intercept, data array[] int J_1, data vector Z_1_1, vector r_1_1) {
    real ptarget = 0;
    int N = end - start + 1;
    // initialize linear predictor term
    vector[N] mu = rep_vector(0.0, N);
    mu += Intercept;
    for (n in 1:N) {
      // add more terms to the linear predictor
      int nn = n + start - 1;
      mu[n] += r_1_1[J_1[nn]] * Z_1_1[nn];
    }
    ptarget += binomial_logit_lpmf(Y[start:end] | trials[start:end], mu);
    return ptarget;
  }
}
data {
  int<lower=1> N;  // total number of observations
  array[N] int Y;  // response variable
  array[N] int trials;  // number of trials
  int grainsize;  // grainsize for threading
  // data for group-level effects of ID 1
  int<lower=1> N_1;  // number of grouping levels
  int<lower=1> M_1;  // number of coefficients per level
  array[N] int<lower=1> J_1;  // grouping indicator per observation
  // group-level predictor values
  vector[N] Z_1_1;
  int prior_only;  // should the likelihood be ignored?
}
transformed data {
  array[N] int seq = sequence(1, N);
}
parameters {
  real Intercept;  // temporary intercept for centered predictors
  vector<lower=0>[M_1] sd_1;  // group-level standard deviations
  array[M_1] vector[N_1] z_1;  // standardized group-level effects
}
transformed parameters {
  vector[N_1] r_1_1;  // actual group-level effects
  real lprior = 0;  // prior contributions to the log posterior
  r_1_1 = (sd_1[1] * (z_1[1]));
  lprior += normal_lpdf(Intercept | -8, 3);
  lprior += cauchy_lpdf(sd_1 | 1, 2)
    - 1 * cauchy_lccdf(0 | 1, 2);
}
model {
  // likelihood including constants
  if (!prior_only) {
    target += reduce_sum(partial_log_lik_lpmf, seq, grainsize, Y, trials, Intercept, J_1, Z_1_1, r_1_1);
  }
  // priors including constants
  target += lprior;
  target += std_normal_lpdf(z_1[1]);
}
generated quantities {
  // actual population-level intercept
  real b_Intercept = Intercept;
}

