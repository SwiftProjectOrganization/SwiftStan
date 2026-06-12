alist(
	log_radon ~ dnorm(mu, sigma),
    mu <- alpha[county] + beta * floor,
	alpha[county] ~ dnorm(0, 10),
	beta ~ dnorm(0, 10),
	sigma ~ dnorm(0, 10)
)
