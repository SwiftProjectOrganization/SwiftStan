alist(
	height ~ dnorm(mu, sigma),
	mu <- a + b*weight,
	a ~ dnorm(100, 8),
	b ~ dnorm(0, 1),
	sigma ~ dnorm(0, 1)
)