alist(
	D ~ dnorm( mu , sigma ) ,
	mu <- a + bM * M ,
	a ~ dnorm( 10 , 10 ) ,
	bM ~ dnorm( 0 , 1 ) ,
	sigma ~ dunif( 0 , 10 )
)
