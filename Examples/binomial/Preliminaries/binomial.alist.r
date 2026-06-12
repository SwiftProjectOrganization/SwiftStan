alist(
    successes ~ dbinom(trials, theta),
    logit(theta) <- a + b * x,
    a ~ dnorm(0, 4),
    b ~ dnorm(0, 1)
)
