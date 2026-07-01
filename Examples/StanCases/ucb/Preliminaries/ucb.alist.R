alist(
	admit ~ dbinom(applications,p),
	logit(p) <- a[dept] + b*male,
	a[dept] ~ dnorm( abar , sigma ),
	abar ~ dnorm( 0 , 4 ),
	sigma ~ dnorm(0, 1),
	b ~ dnorm(0, 1)
)
