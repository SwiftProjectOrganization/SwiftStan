    alist(
        Kcal ~ dnorm( mu , sigma ) ,
        mu <- a + bn * Neo ,
        a ~ dnorm( 0 , 100 ) ,
        bn ~ dnorm( 0 , 1 ) ,
        sigma ~ dunif( 0 , 1 )
    ) ,
