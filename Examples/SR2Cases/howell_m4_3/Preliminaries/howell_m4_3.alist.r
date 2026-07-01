alist(
    height ~ dnorm(mu, sigma),
    mu <- a + b*(weight-44.99),
    a ~ dnorm(100, 8),
    b ~ dlnorm(0, 1),
    sigma ~ dunif(0, 50)
)
