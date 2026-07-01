alist(
    height ~ dnorm(mu, sigma),
    mu <- a + exp(log_b)*(weight-44.99),
    a ~ dnorm(100, 8),
    log_b ~ dnorm(0, 1),
    sigma ~ dunif(0, 50)
)
