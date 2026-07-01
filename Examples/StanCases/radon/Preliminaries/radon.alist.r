alist(
	log_radon ~ dnorm(alpha + beta * floor, sigma),
	alpha ~ dnorm(0, 10),
	beta ~ dnorm(0, 10),
	sigma ~ dnorm(0, 10)
)
