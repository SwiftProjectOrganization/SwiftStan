alist(
	D ~ dnorm( mu , sigma ) ,
	mu <- a + bA * A ,
	a ~ dnorm( 10 , 10 ) ,
	bA ~ dnorm( 0 , 1 ) ,
	sigma ~ dunif( 0 , 10 )
)
