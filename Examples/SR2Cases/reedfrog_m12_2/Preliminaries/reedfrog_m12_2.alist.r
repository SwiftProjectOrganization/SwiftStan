alist(
    surv ~ dbinom( density , p ) ,
    logit(p) <- a_tank[tank] + b_size[size] ,
    a_tank[tank] ~ dnorm( a , a_sigma ) ,
    b_size[size] ~ dnorm( b, b_sigma) ,
    a ~ dnorm(0, 1) ,
    b ~ dnorm(0, 1) ,
    a_sigma ~ dcauchy(0, 1) ,
    b_sigma ~ dcauchy(0, 1)
)
