alist(
  surv ~ dbinom(density, p),
  logit(p) <- a[tank] + s[size],
  a[tank] ~ dnorm(a_bar, sigma_a),
  s[size] ~ dnorm(0, sigma_s),
  a_bar ~ dnorm(0, 1.5),
  sigma_a ~ dnorm(0, 1),
  sigma_s ~ dnorm(0, 1)
)
