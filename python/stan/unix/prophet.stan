// Copyright (c) Facebook, Inc. and its affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

functions {
  matrix get_changepoint_matrix(vector t, vector t_change, int T, int S) {
    // Assumes t and t_change are sorted.
    matrix[T, S] A;
    row_vector[S] a_row;
    int cp_idx;

    // Start with an empty matrix.
    A = rep_matrix(0, T, S);
    a_row = rep_row_vector(0, S);
    cp_idx = 1;

    // Fill in each row of A.
    for (i in 1:T) {
      while ((cp_idx <= S) && (t[i] >= t_change[cp_idx])) {
        a_row[cp_idx] = 1;
        cp_idx = cp_idx + 1;
      }
      A[i] = a_row;
    }
    return A;
  }

  // Logistic trend functions

  vector logistic_gamma(real k, real m, vector delta, vector t_change, int S) {
    vector[S] gamma;  // adjusted offsets, for piecewise continuity
    vector[S + 1] k_s;  // actual rate in each segment
    real m_pr;

    // Compute the rate in each segment
    k_s = append_row(k, k + cumulative_sum(delta));

    // Piecewise offsets
    m_pr = m; // The offset in the previous segment
    for (i in 1:S) {
      gamma[i] = (t_change[i] - m_pr) * (1 - k_s[i] / k_s[i + 1]);
      m_pr = m_pr + gamma[i];  // update for the next segment
    }
    return gamma;
  }

  vector logistic_trend(
    real k,
    real m,
    vector delta,
    vector t,
    vector cap,
    matrix A,
    vector t_change,
    int S
  ) {
    vector[S] gamma;

    gamma = logistic_gamma(k, m, delta, t_change, S);
    return cap .* inv_logit((k + A * delta) .* (t - (m + A * gamma)));
  }

  // Linear trend function

  vector linear_trend(
    real k,
    real m,
    vector delta,
    vector t,
    matrix A,
    vector t_change
  ) {
    return (k + A * delta) .* t + (m + A * (-t_change .* delta));
  }

  // Flat trend function

  vector flat_trend(
    real m,
    int T
  ) {
    return rep_vector(m, T);
  }
}

data {
  int T;                                           // Number of time periods
  int<lower=1> K;                                  // Number of regressors
  vector[T] t;                                     // Time
  vector[T] cap;                                   // Capacities for logistic trend
  vector[T] y;                                     // Time series
  int S;                                           // Number of changepoints
  vector[S] t_change;                              // Times of trend changepoints
  matrix[T,K] X;                                   // Regressors
  vector[K] sigmas;                                // Scale on seasonality prior
  real<lower=0> tau;                               // Scale on changepoints prior
  int trend_indicator;                             // 0 for linear, 1 for logistic
  vector[K] s_a;                                   // Indicator of additive features
  vector[K] s_m;                                   // Indicator of multiplicative features
  int num_constrained;                             // Number of constrained cofficients
  int constrained_beta_idx[num_constrained];       // Indices of constrained coefficients
  int num_unconstrained;                           // Number of unconstrained cofficients
  int unconstrained_beta_idx[num_unconstrained];   // Indices of unconstrained coefficients
}

transformed data {
  matrix[T, S] A;
  A = get_changepoint_matrix(t, t_change, T, S);
}

parameters {
  real k;                   // Base trend growth rate
  real m;                   // Trend offset
  vector[S] delta;          // Trend rate adjustments
  real<lower=0> sigma_obs;  // Observation noise
  vector[num_unconstrained] beta_unconstrained;       // Unconstrained coefficients
  vector<lower=0>[num_constrained] beta_constrained;  // Constrained coefficients
}

transformed parameters {
  vector[T] trend;
  vector[K] beta;
  if (trend_indicator == 0) {
    trend = linear_trend(k, m, delta, t, A, t_change);
  } else if (trend_indicator == 1) {
    trend = logistic_trend(k, m, delta, t, cap, A, t_change, S);
  } else if (trend_indicator == 2) {
    trend = flat_trend(m, T);
  }

  if (num_constrained > 0) {
    for (i in 1:num_constrained) {
      beta[constrained_beta_idx[i]] = beta_constrained[i];
    }
  }
  if (num_unconstrained > 0) {
    for (i in 1:num_unconstrained) {
      beta[unconstrained_beta_idx[i]] = beta_unconstrained[i];
    }
  }
}

model {
  //priors
  k ~ normal(0, 5);
  m ~ normal(0, 5);
  delta ~ double_exponential(0, tau);
  sigma_obs ~ normal(0, 0.5);
  beta ~ normal(0, sigmas);

  // Likelihood
  y ~ normal(
  trend
  .* (1 + X * (beta .* s_m))
  + X * (beta .* s_a),
  sigma_obs
  );
}
