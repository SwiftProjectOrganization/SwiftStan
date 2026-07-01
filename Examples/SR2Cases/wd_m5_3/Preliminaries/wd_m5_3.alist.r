alist(
	D ~ dnorm( mu , sigma ) ,
	mu <- a + bM * M + bA * A ,
	a ~ dnorm( 10 , 10 ) ,
	bM ~ dnorm( 0 , 1 ) ,
	bA ~ dnorm( 0 , 1 ) ,
	sigma ~ dunif( 0 , 10 )
)